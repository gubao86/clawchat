import config from './config.js';
import logger from './utils/logger.js';

export async function sendToGateway(messages, { stream = false, sessionUser = 'clawchat', agentId = 'main' } = {}) {
  const url = `${config.gateway.url}/v1/chat/completions`;
  const body = { model: `openclaw:${agentId}`, messages, stream, user: sessionUser };
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.gateway.token}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    logger.error('Gateway error:', res.status, text);
    throw new Error(`Gateway returned ${res.status}`);
  }
  if (stream) return res;
  const data = await res.json();
  return data.choices?.[0]?.message?.content || '';
}

export async function* streamFromGateway(messages, sessionUser = 'clawchat', agentId = 'main') {
  const res = await sendToGateway(messages, { stream: true, sessionUser, agentId });
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      const payload = trimmed.slice(6);
      if (payload === '[DONE]') return;
      try {
        const chunk = JSON.parse(payload);
        const delta = chunk.choices?.[0]?.delta?.content;
        if (delta) yield delta;
      } catch { /* skip malformed */ }
    }
  }
}
