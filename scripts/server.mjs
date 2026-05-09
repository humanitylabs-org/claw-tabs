#!/usr/bin/env node
import http from "node:http";
import path from "node:path";
import { promises as fs } from "node:fs";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, "..");
const PORT = Number(process.env.CLAWTABS_PORT || 8788);
const HOST = process.env.CLAWTABS_HOST || "127.0.0.1";
const OPENCLAW_CONFIG_PATH = process.env.CLAWTABS_OPENCLAW_CONFIG || "/root/.openclaw/openclaw.json";
const GATEWAY_URL_OVERRIDE = (process.env.CLAWTABS_GATEWAY_URL || "").trim();
const PANELS_STATUS_SCRIPT = path.join(ROOT_DIR, "scripts", "panels-status.sh");
const execFileAsync = promisify(execFile);

function normalizeBasePath(raw = "") {
  const trimmed = String(raw || "").trim();
  if (!trimmed || trimmed === "/") return "/clawtabs";
  const normalized = `/${trimmed.replace(/^\/+|\/+$/g, "")}`;
  return normalized === "/" ? "/clawtabs" : normalized;
}

const BASE_PATH = normalizeBasePath(process.env.CLAWTABS_BASE_PATH || "/clawtabs");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".txt": "text/plain; charset=utf-8",
};

const MANIFEST_MIME = "application/manifest+json";

let cachedBootstrap = { at: 0, value: null };

function respond(res, status, body, headers = {}) {
  const baseHeaders = {
    "Cache-Control": "public, max-age=0, must-revalidate",
    ...headers,
  };
  res.writeHead(status, baseHeaders);
  if (body !== null) res.end(body);
  else res.end();
}

function mimeFor(filePath) {
  if (filePath.endsWith("manifest.json")) return MANIFEST_MIME;
  return MIME[path.extname(filePath).toLowerCase()] || "application/octet-stream";
}

function inferGatewayUrl(req) {
  if (GATEWAY_URL_OVERRIDE) return GATEWAY_URL_OVERRIDE;

  const protoRaw = String(req.headers["x-forwarded-proto"] || "https");
  const hostRaw = String(req.headers["x-forwarded-host"] || req.headers.host || "");

  const proto = protoRaw.split(",")[0].trim() || "https";
  const host = hostRaw.split(",")[0].trim();

  if (!host) return "";
  return `${proto}://${host.replace(/\/+$/, "")}`;
}

async function loadGatewayToken() {
  const now = Date.now();
  if (cachedBootstrap.value && now - cachedBootstrap.at < 15_000) {
    return cachedBootstrap.value;
  }

  try {
    const raw = await fs.readFile(OPENCLAW_CONFIG_PATH, "utf8");
    const parsed = JSON.parse(raw);
    const token = String(parsed?.gateway?.auth?.token || "").trim();
    if (!token) {
      cachedBootstrap = { at: now, value: null };
      return null;
    }
    const value = { token };
    cachedBootstrap = { at: now, value };
    return value;
  } catch {
    cachedBootstrap = { at: now, value: null };
    return null;
  }
}

async function resolveFilePath(requestPath) {
  const relativeRaw = requestPath.slice(BASE_PATH.length) || "/";
  const relative = path.posix.normalize(relativeRaw).replace(/^\/+/, "");
  if (relative.startsWith("..")) return { blocked: true };

  let candidate = relative || "index.html";
  if (!path.extname(candidate) && !candidate.endsWith("/")) {
    candidate += "/";
  }
  if (candidate.endsWith("/")) candidate += "index.html";

  const absolute = path.resolve(ROOT_DIR, candidate);
  if (!(absolute === ROOT_DIR || absolute.startsWith(`${ROOT_DIR}${path.sep}`))) {
    return { blocked: true };
  }

  try {
    const stat = await fs.stat(absolute);
    if (!stat.isFile()) return { missing: true, relative };
    return { path: absolute, relative };
  } catch {
    return { missing: true, relative };
  }
}

async function serveIndex(res, method = "GET") {
  const indexPath = path.join(ROOT_DIR, "index.html");
  const contentType = mimeFor(indexPath);
  const data = method === "HEAD" ? null : await fs.readFile(indexPath);
  respond(res, 200, data, { "Content-Type": contentType });
}

async function loadPanelsStatus() {
  try {
    const { stdout } = await execFileAsync(PANELS_STATUS_SCRIPT, {
      cwd: ROOT_DIR,
      timeout: 6_000,
      maxBuffer: 512 * 1024,
    });

    const parsed = JSON.parse(String(stdout || "{}").trim() || "{}");
    return parsed && typeof parsed === "object"
      ? parsed
      : { ok: false, error: "invalid panels status payload" };
  } catch (err) {
    return {
      ok: false,
      error: "panels status unavailable",
      detail: err instanceof Error ? err.message : "unknown error",
    };
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const method = (req.method || "GET").toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      respond(res, 405, "Method Not Allowed", { "Content-Type": "text/plain; charset=utf-8" });
      return;
    }

    const host = req.headers.host || `${HOST}:${PORT}`;
    const url = new URL(req.url || "/", `http://${host}`);
    const pathname = decodeURIComponent(url.pathname);

    if (pathname === `${BASE_PATH}/api/health`) {
      const body = method === "HEAD" ? null : JSON.stringify({ ok: true, app: "claw-tabs", basePath: BASE_PATH, host: HOST, port: PORT });
      respond(res, 200, body, { "Content-Type": "application/json; charset=utf-8" });
      return;
    }

    if (pathname === `${BASE_PATH}/bootstrap.json`) {
      const tokenRecord = await loadGatewayToken();
      const gatewayUrl = inferGatewayUrl(req);

      if (!tokenRecord?.token || !gatewayUrl) {
        const body = method === "HEAD" ? null : JSON.stringify({ ok: false, error: "bootstrap unavailable" });
        respond(res, 503, body, {
          "Cache-Control": "no-store",
          "Content-Type": "application/json; charset=utf-8",
        });
        return;
      }

      const body = method === "HEAD"
        ? null
        : JSON.stringify({ ok: true, gatewayUrl, token: tokenRecord.token });

      respond(res, 200, body, {
        "Cache-Control": "no-store",
        "Content-Type": "application/json; charset=utf-8",
      });
      return;
    }

    if (pathname === `${BASE_PATH}/api/panels/status`) {
      const status = await loadPanelsStatus();
      const body = method === "HEAD" ? null : JSON.stringify(status);
      respond(res, 200, body, {
        "Cache-Control": "no-store",
        "Content-Type": "application/json; charset=utf-8",
      });
      return;
    }

    if (pathname === BASE_PATH || pathname === `${BASE_PATH}/`) {
      await serveIndex(res, method);
      return;
    }

    if (!pathname.startsWith(`${BASE_PATH}/`)) {
      respond(res, 404, "Not Found", { "Content-Type": "text/plain; charset=utf-8" });
      return;
    }

    const resolved = await resolveFilePath(pathname);
    if (resolved.blocked) {
      respond(res, 403, "Forbidden", { "Content-Type": "text/plain; charset=utf-8" });
      return;
    }

    if (resolved.path) {
      const contentType = mimeFor(resolved.path);
      const data = method === "HEAD" ? null : await fs.readFile(resolved.path);
      respond(res, 200, data, { "Content-Type": contentType });
      return;
    }

    // SPA fallback for client-side routes under /clawtabs/* without an extension.
    if (resolved.missing && !path.extname(resolved.relative || "")) {
      await serveIndex(res, method);
      return;
    }

    respond(res, 404, "Not Found", { "Content-Type": "text/plain; charset=utf-8" });
  } catch (err) {
    respond(res, 500, "Server Error", { "Content-Type": "text/plain; charset=utf-8" });
    console.error("[claw-tabs] request error", err);
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[claw-tabs] serving ${BASE_PATH} at http://${HOST}:${PORT}${BASE_PATH}`);
});
