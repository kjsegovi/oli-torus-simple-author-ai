defmodule Oli.GoogleSlides.GenAITest do
  use ExUnit.Case, async: true

  alias Oli.GoogleSlides.GenAI

  describe "configured?/0" do
    test "returns true when OPENAI_API_KEY is set" do
      original_key = System.get_env("OPENAI_API_KEY")

      on_exit(fn -> restore_env("OPENAI_API_KEY", original_key) end)

      System.put_env("OPENAI_API_KEY", "test-openai-key")

      assert GenAI.configured?()
    end

    test "returns false when OPENAI_API_KEY is blank and no service config is available" do
      original_key = System.get_env("OPENAI_API_KEY")

      on_exit(fn -> restore_env("OPENAI_API_KEY", original_key) end)

      System.delete_env("OPENAI_API_KEY")

      refute GenAI.configured?()
    end
  end

  describe "strip_code_fence/1" do
    test "removes json fences" do
      assert GenAI.strip_code_fence("```json\n{\"a\": 1}\n```") == "{\"a\": 1}"
    end
  end

  defp restore_env(name, value) do
    case value do
      nil -> System.delete_env(name)
      val -> System.put_env(name, val)
    end
  end
end
