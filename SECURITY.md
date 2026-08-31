# Security policy

## Reporting a vulnerability

Please use GitHub's private security-advisory flow for this repository. Do not
open a public issue for a suspected vulnerability or include credentials,
tokens, account data, or proof-of-concept access details in an issue.

## Credential handling

- Never commit API keys, Supabase service-role keys, OAuth secrets, signing
  certificates, or local configuration files.
- Groq API keys are supplied by each user and stored in their local macOS
  Keychain. They are not part of this repository.
- The app's Supabase client identifier is not a service credential. Any
  deployment must enforce Row Level Security and keep privileged keys in the
  server environment only.

If a key is committed accidentally, revoke it at the provider first, then
remove it from every reachable Git ref before publishing a fix.
