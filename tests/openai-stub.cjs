// An OpenAI-compatible model endpoint for the tests, in the place of LiteLLM or
// of a proxy in front of it: it answers /models and /chat/completions (plain
// and streamed, the shape LiteLLM answers with) with the text "pong", and logs
// every request with the Authorization header it carried, so a test sees
// exactly what its client sends. Started with `node -e "$(cat …)"`.
const http = require("http")
const model = "stub-model"
http.createServer((req, res) => {
  let body = ""
  req.on("data", (chunk) => (body += chunk))
  req.on("end", () => {
    console.log("REQUEST", req.method, req.url, "authorization=" + (req.headers.authorization ?? "none"))
    console.log("BODY", body.slice(0, 600))
    try {
      const last = JSON.parse(body).messages?.at(-1)?.content
      if (last) console.log("LAST", JSON.stringify(last).slice(0, 300))
    } catch {}
    if (req.url.endsWith("/models")) {
      res.writeHead(200, { "content-type": "application/json" })
      return res.end(JSON.stringify({ object: "list", data: [{ id: model, object: "model", created: 0, owned_by: "openai" }] }))
    }
    // a real model takes a while; a client that subscribes to the answer after
    // sending the request must still see it
    setTimeout(() => answer(res, body), 2000)
  })
}).listen(4000)

function answer(res, body) {
  const stream = (() => { try { return JSON.parse(body).stream } catch { return false } })()
  const message = { role: "assistant", content: "pong" }
  if (stream) {
    res.writeHead(200, { "content-type": "text/event-stream" })
    res.write("data: " + JSON.stringify({ id: "c1", object: "chat.completion.chunk", created: 0, model, choices: [{ index: 0, delta: message, finish_reason: null }] }) + "\n\n")
    res.write("data: " + JSON.stringify({ id: "c1", object: "chat.completion.chunk", created: 0, model, choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }) + "\n\n")
    return res.end("data: [DONE]\n\n")
  }
  res.writeHead(200, { "content-type": "application/json" })
  res.end(JSON.stringify({ id: "c1", object: "chat.completion", created: 0, model, choices: [{ index: 0, message, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }))
}
