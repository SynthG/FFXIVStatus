# FortniteStatus → Teams

Private GitHub Action that polls `@FortniteStatus` every 10 minutes and posts original (non-reply) posts to a Teams Workflows webhook.

## Setup
1. Create a private GitHub repo and upload these files.
2. Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: `TEAMS_WEBHOOK_URL`
   - Value: your Teams workflow webhook URL
3. Actions → FortniteStatus to Teams → Run workflow once to prime IDs.
4. Leave it. GitHub runs it on a schedule after that.
