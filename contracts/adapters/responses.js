// Shared transport for OpenAI reasoning models. The conversation stays on our server.
function createResponsesClient({ baseUrl, apiKey, model, fetchImpl, timeoutMs }) {
  const url = baseUrl.replace(/\/$/, '') + '/responses';
  return async (input, options) => {
    const response = await fetchImpl(url, {
      method: 'POST',
      signal: AbortSignal.timeout(timeoutMs),
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
      body: JSON.stringify({ model, input, store: false, reasoning: { effort: 'low' }, ...options })
    });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    const result = await response.json();
    if (result.status !== 'completed') throw new Error('Responses request did not complete');
    const text = result.output
      .filter(item => item.type === 'message')
      .flatMap(item => item.content)
      .filter(part => part.type === 'output_text')
      .map(part => part.text)
      .join('');
    return { text, output: result.output };
  };
}

module.exports = { createResponsesClient };
