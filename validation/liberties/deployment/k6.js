import http from "k6/http";
import { check, sleep } from "k6";

const baseUrl = (__ENV.LIBERTIES_URL || "http://127.0.0.1:8000")
  .replace(/\/+$/, "");
const token = __ENV.LIBERTIES_TOKEN || "";
const allowSubmit = __ENV.LIBERTIES_ALLOW_SUBMIT === "YES";
const virtualUsers = Number.parseInt(__ENV.LIBERTIES_VUS || "4", 10);
const duration = __ENV.LIBERTIES_DURATION || "20s";
const p95 = Number.parseInt(
  allowSubmit
    ? (__ENV.LIBERTIES_SUBMIT_P95_MS || "5000")
    : (__ENV.LIBERTIES_P95_MS || "750"),
  10,
);
const jobBody = allowSubmit ? open(__ENV.LIBERTIES_JOB_FILE || "") : "";

export const options = {
  scenarios: allowSubmit
    ? {
        queue_submission: {
          executor: "per-vu-iterations",
          vus: virtualUsers,
          iterations: 1,
          maxDuration: __ENV.LIBERTIES_MAX_DURATION || "2m",
        },
      }
    : {
        read_only: {
          executor: "constant-vus",
          vus: virtualUsers,
          duration,
        },
      },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: [`p(95)<${p95}`],
    checks: ["rate>0.99"],
  },
};

function headers() {
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function securityChecks(response) {
  return check(response, {
    "content type is nosniff": (item) =>
      item.headers["X-Content-Type-Options"] === "nosniff",
    "framing is denied": (item) =>
      item.headers["X-Frame-Options"] === "DENY",
    "responses are not cached": (item) =>
      (item.headers["Cache-Control"] || "").includes("no-store"),
  });
}

export default function () {
  const health = http.get(`${baseUrl}/v1/health`);
  check(health, {
    "health returns 200": (response) => response.status === 200,
    "wire contract is v2": (response) => {
      try {
        return response.json("contract") === "liber.job.wire/2";
      } catch (_) {
        return false;
      }
    },
  });
  securityChecks(health);

  if (!token) {
    const unauthorized = http.get(`${baseUrl}/v1/auth`);
    check(unauthorized, {
      "missing token is rejected": (response) => response.status === 401,
    });
    securityChecks(unauthorized);
    sleep(0.1);
    return;
  }

  const auth = http.get(`${baseUrl}/v1/auth`, { headers: headers() });
  check(auth, {
    "token authenticates": (response) => response.status === 200,
    "auth does not echo bearer token": (response) =>
      !response.body.includes(token),
  });
  securityChecks(auth);

  if (!allowSubmit) {
    const jobs = http.get(`${baseUrl}/v1/jobs`, { headers: headers() });
    check(jobs, {
      "job list returns 200": (response) => response.status === 200,
      "job list has an array": (response) => Array.isArray(response.json("jobs")),
    });
    securityChecks(jobs);
    sleep(0.1);
    return;
  }

  const submitted = http.post(`${baseUrl}/v1/jobs`, jobBody, {
    headers: {
      ...headers(),
      "Content-Type": "application/json",
    },
  });
  check(submitted, {
    "typed job is accepted": (response) => response.status === 200,
    "submitted job has an id": (response) => {
      try {
        return typeof response.json("id") === "string";
      } catch (_) {
        return false;
      }
    },
  });
  securityChecks(submitted);
}
