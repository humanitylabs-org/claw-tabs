#!/bin/bash
# Auto-bump all cache version strings and push to GitHub.
# Clawtabs is local-first (served via tailscale from your own machine), so
# users get updates by pulling from GitHub and re-running ./scripts/setup.sh.
# (The previous Vercel deploy step targeted the retired usemyclaw.com project
# and has been removed.)
set -e

# Bump app.js?v= in index.html
perl -i -pe 's/app\.js\?v=(\d+)/sprintf("app.js?v=%d", $1+1)/e' index.html

# Bump theme.css?v= in index.html
perl -i -pe 's/theme\.css\?v=(\d+)/sprintf("theme.css?v=%d", $1+1)/e' index.html

echo "Versions bumped:"
grep 'app.js?v=' index.html
grep 'theme.css?v=' index.html

git add -A && git commit -m "deploy: bump cache versions" && git push
