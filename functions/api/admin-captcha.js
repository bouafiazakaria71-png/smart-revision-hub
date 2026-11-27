const jsonResponse = (status, payload) => new Response(JSON.stringify(payload), {
  status,
  headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  }
});

export async function onRequestPost({ request, env }) {
  try {
    const requestUrl = new URL(request.url);
    const origin = request.headers.get("Origin");

    if (origin !== requestUrl.origin) {
      return jsonResponse(403, { success: false, error: "invalid_origin" });
    }

    if (!env.TURNSTILE_SECRET_KEY) {
      return jsonResponse(503, { success: false, error: "captcha_not_configured" });
    }

    const rawBody = await request.text();
    if (rawBody.length > 4096) {
      return jsonResponse(413, { success: false, error: "request_too_large" });
    }

    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return jsonResponse(400, { success: false, error: "invalid_json" });
    }

    const token = typeof body?.token === "string" ? body.token.trim() : "";
    if (!token || token.length > 2048) {
      return jsonResponse(400, { success: false, error: "missing_token" });
    }

    const verificationPayload = {
      secret: env.TURNSTILE_SECRET_KEY,
      response: token
    };
    const remoteIp = request.headers.get("CF-Connecting-IP");
    if (remoteIp) verificationPayload.remoteip = remoteIp;

    const verificationResponse = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(verificationPayload)
      }
    );
    if (!verificationResponse.ok) {
      return jsonResponse(502, { success: false, error: "verification_unavailable" });
    }

    const verification = await verificationResponse.json();
    const expectedHostname = requestUrl.hostname.toLowerCase();

    if (
      verification?.success !== true ||
      String(verification.hostname || "").toLowerCase() !== expectedHostname ||
      verification.action !== "admin_access"
    ) {
      return jsonResponse(403, { success: false, error: "captcha_failed" });
    }

    return jsonResponse(200, { success: true });
  } catch (error) {
    console.error("Admin CAPTCHA validation failed:", error?.message || "unknown error");
    return jsonResponse(500, { success: false, error: "verification_error" });
  }
}
