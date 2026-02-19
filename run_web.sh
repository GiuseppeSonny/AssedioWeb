#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT_PROJECT_DIR="$PROJECT_DIR/godot"
EXPORT_DIR="$PROJECT_DIR/export"
FIREBASE_DIR="$PROJECT_DIR/firebase"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
FIREBASE="/usr/local/bin/firebase"
NODE="/usr/local/Cellar/node/24.7.0/bin/node"

echo "=== Assedio Web Build ==="
echo ""

# Check Godot exists
if [ ! -f "$GODOT" ]; then
  echo "ERROR: Godot not found at $GODOT"
  echo "Please install Godot 4 to /Applications/Godot.app"
  exit 1
fi

# Create export dir if needed
mkdir -p "$EXPORT_DIR"

echo ">> Exporting project for Web..."
"$GODOT" --headless --path "$GODOT_PROJECT_DIR" --export-release "Web" "$EXPORT_DIR/index.html"

echo ""
echo ">> Export complete!"
echo ""
echo "============================================"
echo "  UPLOAD THIS FOLDER TO YOUR HOSTING:"
echo "  $EXPORT_DIR"
echo "============================================"
echo ""

# Deploy to Firebase Hosting if --deploy flag is passed
if [[ "$1" == "--deploy" ]]; then
  echo ">> Deploying to Firebase Hosting..."
  "$NODE" "$FIREBASE" deploy --only hosting --project assedio-scirocco
  echo ""
  echo ">> Live at: https://assedio-scirocco.web.app"
  echo ""
fi

echo ">> Freeing port 8080..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true

echo ">> Starting local preview server at http://localhost:8080/"
echo "   (Press Ctrl+C to stop)"
echo ""

cd "$EXPORT_DIR"
python3 - <<'EOF'
import http.server, socketserver

PORT = 8080

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
    def log_message(self, format, *args):
        pass  # suppress request logs

print(f"  Open: http://localhost:{PORT}/")
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF
