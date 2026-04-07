#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────
// stream.mjs — Resilient infinite streaming wrapper for Claude Code
//
// Keeps a genuine Claude Code session alive as long as possible using
// every trick available: model rotation, effort management, rate limit
// header parsing, session recovery, and persistent retry.
//
// Usage:
//   node stream.mjs "your task"
//   node stream.mjs --task-file task.md
//   node stream.mjs --continue              # resume last session
//   echo "task" | node stream.mjs --stdin
//
// ─────────────────────────────────────────────────────────────────────

import { spawn } from "child_process";
import { createInterface } from "readline";
import { readFileSync, appendFileSync, writeFileSync, existsSync } from "fs";
import { randomUUID } from "crypto";

// ═════════════════════════════════════════════════════════════════════
// CONFIG
// ═════════════════════════════════════════════════════════════════════

const config = {
  // Models — primary and fallback (separate rate limit pools)
  primaryModel: "opus",
  fallbackModel: "sonnet",
  currentModel: null, // set at runtime

  // Effort — lower = fewer tokens = longer before rate limit
  workEffort: "high",      // for implementation turns
  evalEffort: "low",       // for evaluation/check turns

  // Limits
  maxTurns: Infinity,      // run forever by default
  maxCostUsd: Infinity,    // no cost limit by default
  pauseBetweenTurns: 1000, // ms

  // Session
  continueMode: false,
  sessionId: null,
  workdir: process.cwd(),

  // Logging
  logFile: "stream.log",
  stateFile: ".stream-state.json",
  verbose: false,

  // Rate limit tracking
  rateLimitState: {
    primaryBlocked: false,
    primaryResetsAt: null,     // epoch seconds
    fallbackBlocked: false,
    fallbackResetsAt: null,
    lastUtilization5h: 0,
    lastUtilization7d: 0,
    consecutiveRateLimits: 0,
  },

  // Task
  task: "",
  taskFile: null,
  readStdin: false,

  // Permissions
  permissionMode: "plan",
};

// ═════════════════════════════════════════════════════════════════════
// CLI ARGUMENT PARSING
// ═════════════════════════════════════════════════════════════════════

const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case "--model":          config.primaryModel = args[++i]; break;
    case "--fallback-model": config.fallbackModel = args[++i]; break;
    case "--effort":         config.workEffort = args[++i]; break;
    case "--eval-effort":    config.evalEffort = args[++i]; break;
    case "--max-turns":      config.maxTurns = parseInt(args[++i]); break;
    case "--max-cost":       config.maxCostUsd = parseFloat(args[++i]); break;
    case "--pause":          config.pauseBetweenTurns = parseInt(args[++i]) * 1000; break;
    case "--continue": case "-c": config.continueMode = true; break;
    case "--session-id":     config.sessionId = args[++i]; break;
    case "--workdir":        config.workdir = args[++i]; break;
    case "--log":            config.logFile = args[++i]; break;
    case "--verbose": case "-v": config.verbose = true; break;
    case "--task-file":      config.taskFile = args[++i]; break;
    case "--stdin":          config.readStdin = true; break;
    case "--permission-mode": config.permissionMode = args[++i]; break;
    case "--help": case "-h":
      console.log(`
stream.mjs — Resilient infinite streaming for Claude Code

Usage:
  node stream.mjs [options] "task description"

Options:
  --model MODEL           Primary model (default: opus)
  --fallback-model MODEL  Fallback when primary rate-limited (default: sonnet)
  --effort LEVEL          Work effort: low|medium|high|max (default: high)
  --eval-effort LEVEL     Evaluation effort (default: low)
  --max-turns N           Max turns (default: unlimited)
  --max-cost USD          Cost ceiling (default: unlimited)
  --pause SECONDS         Pause between turns (default: 1)
  --continue, -c          Resume last session
  --session-id UUID       Specific session
  --task-file FILE        Read task from file
  --stdin                 Read task from stdin
  --permission-mode MODE  Permission mode (default: plan)
  --verbose, -v           Show raw events
`);
      process.exit(0);
    default:
      if (!args[i].startsWith("--")) {
        config.task += (config.task ? " " : "") + args[i];
      }
  }
}

// Load task
if (config.taskFile) {
  config.task = readFileSync(config.taskFile, "utf-8").trim();
}
if (config.readStdin) {
  config.task = readFileSync("/dev/stdin", "utf-8").trim();
}
if (!config.task && !config.continueMode) {
  console.error("Error: provide a task or use --continue");
  process.exit(1);
}

config.currentModel = config.primaryModel;

// ═════════════════════════════════════════════════════════════════════
// TERMINAL OUTPUT
// ═════════════════════════════════════════════════════════════════════

const c = {
  reset: "\x1b[0m", bold: "\x1b[1m", dim: "\x1b[2m",
  red: "\x1b[31m", green: "\x1b[32m", yellow: "\x1b[33m",
  blue: "\x1b[34m", cyan: "\x1b[36m", magenta: "\x1b[35m",
};

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  appendFileSync(config.logFile, line + "\n");
  if (config.verbose) console.log(`${c.dim}${line}${c.reset}`);
}

function print(msg) {
  console.log(msg);
  log(msg.replace(/\x1b\[[0-9;]*m/g, ""));
}

function divider() {
  print(`${c.dim}${"─".repeat(60)}${c.reset}`);
}

function formatCost(usd) {
  if (!usd || usd === 0) return "$0.00";
  if (usd < 0.01) return `${(usd * 100).toFixed(2)}c`;
  return `$${usd.toFixed(4)}`;
}

function formatDuration(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}

// ═════════════════════════════════════════════════════════════════════
// STATE PERSISTENCE
// ═════════════════════════════════════════════════════════════════════

function loadState() {
  try {
    if (existsSync(config.stateFile)) {
      return JSON.parse(readFileSync(config.stateFile, "utf-8"));
    }
  } catch {}
  return null;
}

function saveState(state) {
  writeFileSync(config.stateFile, JSON.stringify(state, null, 2));
}

// ═════════════════════════════════════════════════════════════════════
// RATE LIMIT INTELLIGENCE
// ═════════════════════════════════════════════════════════════════════

/**
 * Choose the best model based on current rate limit state.
 * If primary is blocked, use fallback. If both blocked, wait for
 * whichever resets sooner.
 */
function chooseModel() {
  const rl = config.rateLimitState;
  const now = Date.now() / 1000;

  // Check if primary has recovered
  if (rl.primaryBlocked && rl.primaryResetsAt && now >= rl.primaryResetsAt) {
    rl.primaryBlocked = false;
    rl.primaryResetsAt = null;
    log("Primary model rate limit reset");
  }

  // Check if fallback has recovered
  if (rl.fallbackBlocked && rl.fallbackResetsAt && now >= rl.fallbackResetsAt) {
    rl.fallbackBlocked = false;
    rl.fallbackResetsAt = null;
    log("Fallback model rate limit reset");
  }

  if (!rl.primaryBlocked) {
    config.currentModel = config.primaryModel;
    return config.primaryModel;
  }

  if (!rl.fallbackBlocked) {
    config.currentModel = config.fallbackModel;
    return config.fallbackModel;
  }

  // Both blocked — return whichever resets sooner
  const primaryWait = (rl.primaryResetsAt || Infinity) - now;
  const fallbackWait = (rl.fallbackResetsAt || Infinity) - now;

  if (primaryWait <= fallbackWait) {
    config.currentModel = config.primaryModel;
    return config.primaryModel;
  } else {
    config.currentModel = config.fallbackModel;
    return config.fallbackModel;
  }
}

/**
 * Calculate how long to wait if both models are blocked.
 * Returns 0 if at least one model is available.
 */
function getWaitTime() {
  const rl = config.rateLimitState;
  const now = Date.now() / 1000;

  if (!rl.primaryBlocked || !rl.fallbackBlocked) return 0;

  const primaryWait = Math.max(0, (rl.primaryResetsAt || 0) - now);
  const fallbackWait = Math.max(0, (rl.fallbackResetsAt || 0) - now);

  return Math.min(primaryWait, fallbackWait) * 1000; // ms
}

/**
 * Update rate limit state from a stream event or error.
 */
function handleRateLimitEvent(event, model) {
  const rl = config.rateLimitState;
  rl.consecutiveRateLimits++;

  // Parse utilization from event if available
  if (event?.utilization_5h !== undefined) {
    rl.lastUtilization5h = event.utilization_5h;
  }
  if (event?.utilization_7d !== undefined) {
    rl.lastUtilization7d = event.utilization_7d;
  }

  log(`Rate limit hit on ${model} (consecutive: ${rl.consecutiveRateLimits})`);
}

/**
 * Mark a model as blocked with a specific reset time.
 */
function markModelBlocked(model, resetsAt) {
  const rl = config.rateLimitState;
  if (model === config.primaryModel) {
    rl.primaryBlocked = true;
    rl.primaryResetsAt = resetsAt;
    log(`Primary model blocked until ${new Date(resetsAt * 1000).toISOString()}`);
  } else {
    rl.fallbackBlocked = true;
    rl.fallbackResetsAt = resetsAt;
    log(`Fallback model blocked until ${new Date(resetsAt * 1000).toISOString()}`);
  }
}

/**
 * Reset consecutive rate limit counter on successful response.
 */
function handleSuccessfulResponse() {
  config.rateLimitState.consecutiveRateLimits = 0;
}

// ═════════════════════════════════════════════════════════════════════
// CLAUDE CODE PROCESS MANAGEMENT
// ═════════════════════════════════════════════════════════════════════

/**
 * Run a single Claude Code turn. Returns parsed result.
 *
 * Key design: we set CLAUDE_CODE_UNATTENDED_RETRY=1 so the inner
 * claude process never gives up on rate limits — it waits internally
 * with 30s heartbeats. Our outer loop only needs to handle model
 * switching and session continuity.
 */
function runTurn(prompt, options = {}) {
  return new Promise((resolve, reject) => {
    const model = options.model || chooseModel();
    const effort = options.effort || config.workEffort;

    const cmdArgs = [
      "-p",
      "--model", model,
      "--output-format", "stream-json",
      "--verbose",
      "--permission-mode", config.permissionMode,
      "--effort", effort,
    ];

    if (options.continueSession) {
      cmdArgs.push("-c");
    } else if (config.sessionId) {
      cmdArgs.push("--session-id", config.sessionId);
    }

    if (config.fallbackModel && config.fallbackModel !== model) {
      cmdArgs.push("--fallback-model", config.fallbackModel);
    }

    cmdArgs.push(prompt);

    log(`Turn: model=${model} effort=${effort} continue=${!!options.continueSession}`);

    const child = spawn("claude", cmdArgs, {
      cwd: config.workdir,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        CLAUDE_CODE_UNATTENDED_RETRY: "1",
        CLAUDE_CODE_EAGER_FLUSH: "1",
      },
    });

    let assistantText = "";
    let sessionId = null;
    let toolCalls = 0;
    let tokensIn = 0;
    let tokensOut = 0;
    let costUsd = 0;
    let rateLimitEvents = 0;
    const startTime = Date.now();

    const rl = createInterface({ input: child.stdout });
    rl.on("line", (line) => {
      try {
        const event = JSON.parse(line);

        switch (event.type) {
          case "system":
            if (event.session_id) {
              sessionId = event.session_id;
            }
            break;

          case "assistant":
            if (event.message?.content) {
              for (const block of event.message.content) {
                if (block.type === "text") {
                  assistantText += block.text;
                }
              }
            }
            break;

          case "content_block_delta":
            if (event.delta?.type === "text_delta" && config.verbose) {
              process.stdout.write(`${c.dim}${event.delta.text}${c.reset}`);
            }
            break;

          case "tool_use":
            toolCalls++;
            const name = event.name || event.tool_name || "?";
            print(`  ${c.cyan}tool:${c.reset} ${name}`);
            break;

          case "rate_limit_event":
            rateLimitEvents++;
            handleRateLimitEvent(event, model);
            break;

          case "result":
            if (event.result) {
              assistantText = "";
              for (const block of event.result) {
                if (block.type === "text") assistantText += block.text;
              }
            }
            if (event.usage) {
              tokensIn += event.usage.input_tokens || 0;
              tokensOut += event.usage.output_tokens || 0;
            }
            if (event.cost_usd) costUsd = event.cost_usd;
            if (event.session_id) sessionId = event.session_id;
            handleSuccessfulResponse();
            break;
        }
      } catch {
        // Non-JSON line, ignore
      }
    });

    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      log(`stderr: ${chunk.toString().trim()}`);
    });

    child.on("close", (code) => {
      if (config.verbose) process.stdout.write("\n");

      const duration = Date.now() - startTime;

      // Handle rate limit exit — claude process gave up
      if (code !== 0 && stderr.includes("rate limit")) {
        // Mark current model as blocked, estimate 5min reset
        const estimatedReset = Date.now() / 1000 + 300;
        markModelBlocked(model, estimatedReset);

        resolve({
          text: assistantText,
          sessionId,
          toolCalls,
          tokensIn,
          tokensOut,
          costUsd,
          duration,
          rateLimited: true,
          exitCode: code,
        });
        return;
      }

      if (code !== 0 && !assistantText) {
        reject(new Error(`Exit ${code}: ${stderr.slice(0, 500)}`));
        return;
      }

      resolve({
        text: assistantText,
        sessionId,
        toolCalls,
        tokensIn,
        tokensOut,
        costUsd,
        duration,
        rateLimited: false,
        exitCode: code,
      });
    });

    child.on("error", reject);
  });
}

// ═════════════════════════════════════════════════════════════════════
// EVALUATION
// ═════════════════════════════════════════════════════════════════════

async function evaluateProgress(task) {
  const prompt = `Review progress on the task. Respond with exactly one JSON object (no fences):
{"status":"COMPLETE"|"IN_PROGRESS"|"BLOCKED"|"ERROR","summary":"what was done","next":"what to do next"}`;

  try {
    const result = await runTurn(prompt, {
      continueSession: true,
      effort: config.evalEffort,
      model: config.fallbackModel, // use cheaper model for evals
    });

    const match = result.text.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      return {
        status: parsed.status || "IN_PROGRESS",
        summary: parsed.summary || "",
        next: parsed.next || "Continue.",
        costUsd: result.costUsd || 0,
      };
    }
  } catch (e) {
    log(`Eval error: ${e.message}`);
  }

  return { status: "IN_PROGRESS", summary: "?", next: "Continue.", costUsd: 0 };
}

// ═════════════════════════════════════════════════════════════════════
// SLEEP
// ═════════════════════════════════════════════════════════════════════

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

// ═════════════════════════════════════════════════════════════════════
// SIGNAL HANDLING
// ═════════════════════════════════════════════════════════════════════

let shuttingDown = false;

function gracefulShutdown(stats) {
  if (shuttingDown) return;
  shuttingDown = true;
  print(`\n${c.yellow}Shutting down gracefully...${c.reset}`);
  saveState({
    ...stats,
    rateLimitState: config.rateLimitState,
    timestamp: new Date().toISOString(),
  });
  print(`State saved to ${config.stateFile}`);
  process.exit(0);
}

// ═════════════════════════════════════════════════════════════════════
// MAIN LOOP
// ═════════════════════════════════════════════════════════════════════

async function main() {
  writeFileSync(config.logFile, `# stream.mjs — ${new Date().toISOString()}\n`);

  // Restore state if continuing
  let state = config.continueMode ? loadState() : null;
  if (state) {
    config.sessionId = state.sessionId;
    config.task = state.task || config.task;
    config.rateLimitState = state.rateLimitState || config.rateLimitState;
    print(`${c.yellow}Resuming session ${state.sessionId} (turn ${(state.iteration || 0) + 1})${c.reset}`);
  }

  let iteration = state?.iteration || 0;
  let totalCost = state?.totalCost || 0;
  let totalToolCalls = state?.totalToolCalls || 0;
  let totalTokensIn = state?.totalTokensIn || 0;
  let totalTokensOut = state?.totalTokensOut || 0;
  let status = "IN_PROGRESS";
  const startTime = Date.now();

  const stats = () => ({
    sessionId: config.sessionId,
    task: config.task,
    iteration,
    totalCost,
    totalToolCalls,
    totalTokensIn,
    totalTokensOut,
    status,
  });

  // Signal handlers
  process.on("SIGINT", () => gracefulShutdown(stats()));
  process.on("SIGTERM", () => gracefulShutdown(stats()));

  print(`${c.bold}stream.mjs${c.reset} — resilient infinite streaming`);
  print(`${c.dim}Task: ${config.task.slice(0, 100)}${config.task.length > 100 ? "..." : ""}${c.reset}`);
  print(`${c.dim}Primary: ${config.primaryModel} | Fallback: ${config.fallbackModel} | Effort: ${config.workEffort}/${config.evalEffort}${c.reset}`);
  divider();

  while (iteration < config.maxTurns && status === "IN_PROGRESS") {
    iteration++;

    // ── Cost check ──
    if (totalCost >= config.maxCostUsd) {
      print(`${c.red}Cost limit reached: ${formatCost(totalCost)} >= ${formatCost(config.maxCostUsd)}${c.reset}`);
      status = "BUDGET_EXCEEDED";
      break;
    }

    // ── Rate limit wait ──
    const waitMs = getWaitTime();
    if (waitMs > 0) {
      print(`${c.yellow}Both models rate-limited. Waiting ${formatDuration(waitMs)}...${c.reset}`);
      log(`Rate limit wait: ${waitMs}ms`);
      await sleep(waitMs + 5000); // 5s buffer past reset
    }

    // ── Choose model ──
    const model = chooseModel();
    const elapsed = formatDuration(Date.now() - startTime);

    print(`\n${c.blue}${c.bold}[Turn ${iteration}]${c.reset} ${c.dim}model=${model} cost=${formatCost(totalCost)} elapsed=${elapsed}${c.reset}`);

    // ── Build prompt ──
    let prompt;
    const isFirst = iteration === 1 && !config.continueMode;

    if (isFirst) {
      prompt = `${config.task}

Work step by step. Be thorough — read existing code before modifying, run tests after changes. After each major step, state what you did and what comes next.`;
    } else {
      prompt = `Continue working on the task. Reminder:

"${config.task.slice(0, 500)}"

Pick up where you left off. Do the next step.`;
    }

    // ── Execute turn ──
    let result;
    try {
      result = await runTurn(prompt, {
        continueSession: !isFirst,
        model,
      });

      totalCost += result.costUsd || 0;
      totalToolCalls += result.toolCalls;
      totalTokensIn += result.tokensIn;
      totalTokensOut += result.tokensOut;

      if (result.sessionId) {
        config.sessionId = result.sessionId;
      }

      // Show summary
      if (result.text) {
        const preview = result.text.split("\n").slice(0, 3).join("\n").slice(0, 200);
        if (preview.trim()) print(`${c.dim}${preview}${preview.length < result.text.length ? "..." : ""}${c.reset}`);
      }
      print(`${c.dim}  tools:${result.toolCalls} tok:${result.tokensIn}→${result.tokensOut} cost:${formatCost(result.costUsd)} time:${formatDuration(result.duration)}${c.reset}`);

      if (result.rateLimited) {
        print(`${c.yellow}Rate limited on ${model}. Switching...${c.reset}`);
        continue; // re-enter loop, chooseModel() picks fallback
      }

    } catch (e) {
      print(`${c.red}Error: ${e.message}${c.reset}`);
      log(`Turn ${iteration} error: ${e.stack}`);

      if (e.message.includes("overloaded") || e.message.includes("rate") || e.message.includes("429")) {
        const estimatedReset = Date.now() / 1000 + 300;
        markModelBlocked(model, estimatedReset);
        print(`${c.yellow}Marked ${model} as blocked. Retrying...${c.reset}`);
        iteration--; // retry
        await sleep(5000);
        continue;
      }

      // Non-retryable error — wait and retry anyway
      print(`${c.yellow}Unexpected error. Retrying in 30s...${c.reset}`);
      await sleep(30000);
      iteration--;
      continue;
    }

    divider();

    // ── Evaluate progress ──
    print(`${c.dim}Evaluating...${c.reset}`);
    const evaluation = await evaluateProgress(config.task);
    totalCost += evaluation.costUsd;
    status = evaluation.status;

    switch (status) {
      case "COMPLETE":
        print(`${c.green}${c.bold}Complete!${c.reset} ${c.dim}${evaluation.summary}${c.reset}`);
        break;
      case "BLOCKED":
        print(`${c.yellow}${c.bold}Blocked.${c.reset} ${c.dim}${evaluation.summary}${c.reset}`);
        break;
      case "ERROR":
        print(`${c.red}${c.bold}Error.${c.reset} ${c.dim}${evaluation.summary}${c.reset}`);
        break;
      case "IN_PROGRESS":
        print(`${c.blue}Next: ${evaluation.next}${c.reset}`);
        break;
    }

    // ── Save state ──
    saveState({
      ...stats(),
      lastEvaluation: evaluation,
      rateLimitState: config.rateLimitState,
      timestamp: new Date().toISOString(),
    });

    // ── Pause ──
    if (status === "IN_PROGRESS" && iteration < config.maxTurns) {
      await sleep(config.pauseBetweenTurns);
    }
  }

  // ── Final report ──
  divider();
  const elapsed = formatDuration(Date.now() - startTime);
  print(`\n${c.bold}Done${c.reset}`);
  print(`  Status:     ${status}`);
  print(`  Turns:      ${iteration}`);
  print(`  Tools:      ${totalToolCalls}`);
  print(`  Tokens:     ${totalTokensIn} in / ${totalTokensOut} out`);
  print(`  Cost:       ${formatCost(totalCost)}`);
  print(`  Duration:   ${elapsed}`);
  print(`  Session:    ${config.sessionId || "N/A"}`);

  if (status === "IN_PROGRESS") {
    print(`\n${c.yellow}Resume: node stream.mjs --continue${c.reset}`);
  }

  saveState({
    ...stats(),
    rateLimitState: config.rateLimitState,
    timestamp: new Date().toISOString(),
    completed: status === "COMPLETE",
  });
}

main().catch((e) => {
  console.error(`${c.red}Fatal: ${e.message}${c.reset}`);
  log(`Fatal: ${e.stack}`);
  process.exit(1);
});
