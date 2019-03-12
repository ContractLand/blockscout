defmodule EthereumJSONRPC.Contract do
  @moduledoc """
  Smart contract functions executed by `eth_call`.
  """

  import EthereumJSONRPC, only: [integer_to_quantity: 1, json_rpc: 2, request: 1]

  alias EthereumJSONRPC.Encoder

  @typedoc """
  Call to a smart contract function.

  * `:block_number` - the block in which to execute the function. Defaults to the `nil` to indicate
  the latest block as determined by the remote node, which may differ from the latest block number
  in `Explorer.Chain`.
  """
  @type call :: %{
          required(:contract_address) => String.t(),
          required(:function_name) => String.t(),
          required(:args) => [term()],
          optional(:block_number) => EthereumJSONRPC.block_number()
        }

  @typedoc """
  Result of calling a smart contract function.
  """
  @type call_result :: {:ok, term()} | {:error, String.t()}

  @spec execute_contract_functions([call()], [map()], EthereumJSONRPC.json_rpc_named_arguments()) :: [call_result()]
  def execute_contract_functions(requests, abi, json_rpc_named_arguments) do
    functions =
      abi
      |> ABI.parse_specification()
      |> Enum.into(%{}, &{&1.function, &1})

    requests_with_index = Enum.with_index(requests)

    {:ok, responses} =
      requests_with_index
      |> Enum.map(fn {%{contract_address: contract_address, function_name: function_name, args: args} = request, index} ->
        functions[function_name]
        |> Encoder.encode_function_call(args)
        |> eth_call_request(contract_address, index, Map.get(request, :block_number))
      end)
      |> json_rpc(json_rpc_named_arguments)

    indexed_responses = Enum.into(responses, %{}, &{&1.id, &1})

    Enum.map(requests_with_index, fn {%{function_name: function_name}, index} ->
      {^index, result} = Encoder.decode_result(indexed_responses[index], functions[function_name])
      result
    end)
  rescue
    error ->
      format_error(error)
  end

  defp eth_call_request(data, contract_address, id, block_number) do
    block =
      case block_number do
        nil -> "latest"
        block_number -> integer_to_quantity(block_number)
      end

    request(%{
      id: id,
      method: "eth_call",
      params: [%{to: contract_address, data: data}, block]
    })
  end

  #   defp decode_results({:error, {:bad_gateway, _request_url}}) do
  #     format_error("Bad Gateway")
  #   end

  defp format_error(message) when is_binary(message) do
    {:error, message}
  end

  defp format_error(%{message: error_message}) do
    format_error(error_message)
  end

  defp format_error(error) do
    format_error(Exception.message(error))
  end
end
