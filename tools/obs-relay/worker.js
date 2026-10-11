// OBS erişim relay'i (Cloudflare Worker).
//
// Supabase Edge Function'dan gelen istekleri şeffafça
// https://obs.alparslan.edu.tr'e yönlendirir: yol, sorgu, gövde ve
// başlıklar (özellikle Cookie/Set-Cookie) aynen korunur.
//
// Deploy: npx wrangler login
//         npx wrangler deploy tools/obs-relay/worker.js --name obs-relay

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = new URL(
      url.pathname + url.search,
      "https://obs.alparslan.edu.tr",
    );

    const headers = new Headers(request.headers);
    headers.delete("host");

    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    const upstream = await fetch(target.toString(), {
      method: request.method,
      headers,
      body: hasBody ? request.body : undefined,
      // Login POST'unun302'si ham dönmeli; relay yönlendirmeyi yutarsa
      // OBS'in gerçek hata mesajı kaybolur.
      redirect: "manual",
    });

    const out = new Headers(upstream.headers);
    const setCookies = typeof upstream.headers.getAll === "function"
      ? upstream.headers.getAll("set-cookie")
      : [];
    if (setCookies.length) {
      out.delete("set-cookie");
      for (const cookie of setCookies) out.append("set-cookie", cookie);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      headers: out,
    });
  },
};
