# frozen_string_literal: true

module ResponseFixtures
  def response_fixture(content: '{"score":0.9,"reasoning":"offline"}', protocol: :responses, status: 200, error: nil)
    body = if error
             { error: { message: error, type: "fixture_error", code: "fixture_error" } }
           else
             public_send("#{protocol}_body", content)
           end
    [status, { "Content-Type" => "application/json" }, JSON.generate(body)]
  end

  def responses_body(content)
    {
      id: "resp_offline", model: "gpt-4o", status: "completed",
      output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text: content }] }],
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  def chat_completions_body(content)
    {
      id: "chatcmpl_offline", model: "gpt-4o",
      choices: [{ message: { role: "assistant", content: }, finish_reason: "stop" }],
      usage: { prompt_tokens: 10, completion_tokens: 5 }
    }
  end

  def anthropic_body(content)
    {
      id: "msg_offline", type: "message", role: "assistant", model: "claude-sonnet-4",
      content: [{ type: "text", text: content }], stop_reason: "end_turn",
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  def gemini_body(content)
    {
      candidates: [{ content: { role: "model", parts: [{ text: content }] }, finishReason: "STOP" }],
      usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5, totalTokenCount: 15 },
      modelVersion: "gemini-2.5-flash"
    }
  end
end
