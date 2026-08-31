// Supabase Edge Function: auth-redirect
// Receives the OAuth callback from Supabase (with tokens in the URL fragment)
// and redirects to the macOS app's custom URL scheme.
//
// Deploy with: supabase functions deploy auth-redirect

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  // The tokens will be in the URL fragment (not accessible server-side directly),
  // so we serve an HTML page that reads the fragment client-side and redirects.
  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Signing you in to PodTrackio...</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      background: #0b111a;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
      flex-direction: column;
      gap: 16px;
    }
    .spinner {
      width: 36px; height: 36px;
      border: 3px solid rgba(0,209,224,0.2);
      border-top-color: #00d1e0;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    p { color: rgba(255,255,255,0.6); font-size: 14px; }
  </style>
</head>
<body>
  <div class="spinner"></div>
  <p>Completing authentication — returning to PodTrackio&hellip;</p>
  <script>
    // Read tokens from the URL fragment (e.g. #access_token=...&refresh_token=...)
    const fragment = window.location.hash.substring(1);
    if (fragment) {
      // Redirect to macOS custom URL scheme with the token fragment intact
      window.location.href = 'podtrackio://auth-callback#' + fragment;
    } else {
      // Check if tokens are in query params (some flows send them differently)
      const params = window.location.search;
      if (params) {
        window.location.href = 'podtrackio://auth-callback' + params;
      } else {
        document.querySelector('p').textContent = 'Authentication failed. Please try again.';
      }
    }
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // Allow the redirect to open the custom URL scheme
      "Content-Security-Policy": "default-src 'self'; script-src 'unsafe-inline'",
    },
  });
});
