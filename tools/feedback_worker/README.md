# Feedback Worker

Cloudflare Worker that relays the in-game bug report form (F7,
`autoloads/feedback_reporter.gd`) to a Discord channel. The game only knows
this Worker's URL; the Discord webhook lives here as a secret, so it can't be
pulled out of the `.pck`.

```
game ──multipart──▶ Worker /report ──embed + files──▶ Discord webhook
        (X-Game-Key)   validate, 3/min/IP
```

## One-time setup

1. In Discord, open **Channel settings → Integrations → Webhooks → New Webhook**
   and copy the webhook URL.
2. Deploy:
   ```sh
   cd tools/feedback_worker
   npm install
   npx wrangler login
   npx wrangler secret put DISCORD_WEBHOOK_URL   # paste the webhook URL
   npx wrangler deploy
   ```
   `deploy` prints the Worker URL, e.g.
   `https://feedback-game-template.<your-subdomain>.workers.dev`.
3. Set `FEEDBACK_ENDPOINT` in `autoloads/feedback_reporter.gd` to that URL plus
   `/report`. Until it's set, the form opens but Send stays disabled.

## Day to day

- `npx wrangler tail`: live logs (Discord rejections are logged here).
- Rotate the webhook: create a new one in Discord, run `wrangler secret put`
  again, then delete the old webhook. No game patch needed.
- Tune the limits: `[[ratelimits]]` in `wrangler.toml` (period must be 10 or
  60 s) and the size caps at the top of `src/index.js`.
- `GAME_KEY` must match `FeedbackReporter.GAME_KEY`. Changing it locks out
  every build already shipped.

## Local testing

```sh
echo 'DISCORD_WEBHOOK_URL=<webhook url>' > .dev.vars   # gitignored
npx wrangler dev                                       # http://localhost:8787

curl -i http://localhost:8787/report -H 'X-Game-Key: CHANGE-ME' \
  -F category=bug -F 'message=test from curl' -F 'context={"version":"dev"}'
```

To point the game at it, launch with
`FEEDBACK_ENDPOINT_OVERRIDE=http://localhost:8787/report`.
