#!/usr/bin/env bun

const { readdirSync, statSync, readFileSync } = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");
const ignore = require("ignore");

const NAME = "p";
const NAME_UPC = NAME.toUpperCase();

let DEFAULT_OPTS = '';

const DEFAULT_IGNORE = `
*.app
node_modules
venv
.pnpm
.cache
Library
*.xcodeproj
*.localized
com_apple_*
Packages
.git
`;

function log(message) {
  if (process.env.DEBUG === "true") {
    console.log(`\x1b[34m${message}\x1b[0m`);
  }
}

function createIgnoreFilter(baseDir) {
  const ig = ignore();
  const ignoreFiles = [".gitignore", ".nomedia", ".ignore"];
  for (const file of ignoreFiles) {
    try {
      const filePath = path.join(baseDir, file);
      const content = readFileSync(filePath, "utf8");
      ig.add(content);
    } catch (err) {}
  }
  ig.add(DEFAULT_IGNORE);
  return ig;
}

function fuzzyMatch(str, pattern) {
  const _log = (msg) => {};

  _log(`Fuzzy matching "${str}" against pattern "${pattern}"`);

  if (!pattern) return { matched: false, score: 0, reasons: [] };

  let score = 0;
  let patternIdx = 0;
  let consecutive = 0;
  let reasons = [];

  const lowerStr = str.toLowerCase();
  const lowerPattern = pattern.toLowerCase();

  const matches = new Array(pattern.length);
  const positions = [];

  if (!lowerStr.includes(lowerPattern[0])) {
    _log(`No match - first character "${lowerPattern[0]}" not found in string`);
    return { matched: false, score: 0, reasons: [] };
  }
  if (lowerStr === lowerPattern) {
    _log("Exact match");
    score += 20;
    reasons.push({ why: "Exact match bonus", amount: 20 });
  }
  for (
    let strIdx = 0;
    strIdx < str.length && patternIdx < pattern.length;
    strIdx++
  ) {
    if (lowerStr[strIdx] === lowerPattern[patternIdx]) {
      matches[patternIdx] = str[strIdx];
      positions.push(strIdx);

      if (strIdx === 0 || ["-", "_", "."].includes(str[strIdx - 1])) {
        score += 10;
        reasons.push({ why: "Start bonus", amount: 10 });
      }

      if (str[strIdx] === pattern[patternIdx]) {
        score += 8;
        reasons.push({ why: "Case matching bonus", amount: 8 });
      }

      if (
        positions.length > 1 &&
        positions[positions.length - 1] === positions[positions.length - 2] + 1
      ) {
        consecutive++;
        const MULTIPLIER = 3;
        score += consecutive * MULTIPLIER;
        reasons.push({
          why: `Consecutive bonus`,
          amount: consecutive * MULTIPLIER,
        });
      } else {
        consecutive = 0;
      }

      patternIdx++;
    }
  }

  if (patternIdx !== pattern.length) {
    _log("Failed to match all pattern characters");
    return { matched: false, score: 0, reasons: [] };
  }

  const proximity = positions.reduce((sum, pos, idx) => {
    if (idx > 0) {
      const gap = pos - positions[idx - 1];
      return sum + Math.max(0, 5 - gap);
    }
    return sum;
  }, 0);

  score += proximity;
  reasons.push({ why: "Proximity bonus", amount: proximity });

  const lengthPenalty = (str.length - pattern.length) * 0.5;
  score -= lengthPenalty;
  reasons.push({ why: "Length penalty", amount: -lengthPenalty });

  return {
    matched: true,
    score: score,
    positions: positions,
    reasons: reasons,
  };
}

function closest(searchDir, lookfor, depth = 0, maxDepth = 3, ig = null) {
  log(`Searching directory: ${searchDir}`);

  if (!ig) {
    ig = createIgnoreFilter(searchDir);
  }

  try {
    let matches = [];
    let items;
    try {
      items = readdirSync(searchDir);
    } catch (err) {
      if (err.code === "EACCES") {
        log(`Permission denied: ${searchDir}`);
        items = [];
      } else if (err.code === "ENOTDIR") {
        log(`Not a directory: ${searchDir}`);
        items = [];
      } else {
        throw err;
      }
    }

    log(`Found ${items.length} items to check`);

    for (const item of items) {
      try {
        const fullPath = path.join(searchDir, item);
        const stats = statSync(fullPath);

        if (ig.ignores(path.relative(searchDir, fullPath))) {
          log(`Ignoring path: ${fullPath}`);
          continue;
        }

        if (stats.isDirectory()) {
          log(`Checking directory: ${item}`);
          const match = fuzzyMatch(item, lookfor);
          if (match.matched) {
            log(`Match found: ${item} (score: ${match.score})`);
            matches.push({
              path: fullPath,
              score: match.score,
              name: item,
              depth: depth + 1,
              reasons: match.reasons,
            });
          }
          if (depth < maxDepth) {
            const subMatches = closest(
              fullPath,
              lookfor,
              depth + 1,
              maxDepth,
              ig,
            );
            matches.push(...subMatches);
          }
        }
      } catch (err) {
        log(`Skipping inaccessible item: ${item}`);
      }
    }

    if (matches.length === 0) {
      return matches;
    }
    matches = matches.sort((a, b) => b.score - a.score);
    return matches;
  } catch (err) {
    console.error(`Error accessing directory ${searchDir}:`, err);
    return [];
  }
}

function searchUp(startDir, lookfor) {
  log(`Starting upward search from: ${startDir}`);
  let currentDir = path.resolve(startDir, "..");
  let matches = [];

  while (true) {
    matches = closest(currentDir, lookfor, 0, 3);
    log(`Found ${matches.length} matches in ${currentDir}`);

    if (matches.length > 0 || currentDir === path.parse(currentDir).root) {
      break;
    }
    currentDir = path.dirname(currentDir);
    log(`Moving up to parent directory: ${currentDir}`);
  }

  return matches;
}

async function selectWithFzf(matches) {
  return new Promise((resolve) => {
    log("Launching fzf for selection");

    const entries = matches.map(
      (m) => `${m.path} (score: ${(m.fullScore || m.score).toFixed(1)})`,
    );

    const fzf = spawn("fzf", ["--height", "40%", "--reverse"], {
      stdio: ["pipe", "pipe", "inherit"],
    });

    let output = "";
    fzf.stdout.on("data", (data) => {
      output += data.toString();
    });

    fzf.on("close", (code) => {
      if (code === 0) {
        const path = output.trim().split(" (score:")[0];
        log(`Selected: ${path}`);
        resolve(path);
      } else {
        log("No selection made");
        resolve(null);
      }
    });

    fzf.stdin.write(entries.join("\n"));
    fzf.stdin.end();
  });
}

const INIT_COMMAND_PREFIX = `___${NAME_UPC}_INIT_CMD:`;

function generateInitScript(shell) {
  switch (shell) {
    case "zsh":
      return `
# Add this to your .zshrc
${NAME}() {
  local output
  output="$(${NAME_UPC}_SHELL_INTEGRATION=1 command ${DEFAULT_OPTS} ${NAME} "$@")"
  if [[ $output == ${CD_COMMAND_PREFIX}* ]]; then
    cd "\${output#${CD_COMMAND_PREFIX}}"
  else
    echo "$output"
  fi
}
`;
    case "bash":
      return `
# Add this to your .bashrc
${NAME}() {
  local output
  output="$(${NAME_UPC}_SHELL_INTEGRATION=1 command ${DEFAULT_OPTS} ${NAME} "$@")"
  if [[ $output == ${CD_COMMAND_PREFIX}* ]]; then
    cd "\${output#${CD_COMMAND_PREFIX}}"
  else
    echo "$output"
  fi
}
`;
    case "fish":
      return `
# Add this to your config.fish
function ${NAME}
  set output (env ${NAME_UPC}_SHELL_INTEGRATION=1 command ${DEFAULT_OPTS} ${NAME} $argv)
  if string match -q "${CD_COMMAND_PREFIX}*" -- \$output
    cd (string replace "${CD_COMMAND_PREFIX}" "" -- \$output)
  else
    echo \$output
  end
end
`;
    default:
      throw new Error(`Unsupported shell: ${shell}`);
  }
}
const SHELL_INTEGRATION_ENV = `${NAME_UPC}_SHELL_INTEGRATION`;
const CD_COMMAND_PREFIX = `___${NAME_UPC}_CD_CMD:`;

function isShellIntegrationEnabled() {
  return !!process.env[SHELL_INTEGRATION_ENV];
}

function outputCdCommand(dir) {
  if (isShellIntegrationEnabled()) {
    console.log(`${CD_COMMAND_PREFIX}${dir}`);
  } else {
    log(
      `Shell integration not detected. To enable directory changing, use \`${NAME} --init [shell]\` to generate the necessary script.`,
    );
    console.log(dir);
  }
}
const SUPPORTED_SHELLS = ["bash", "zsh", "fish"];

function getCurrentShell() {
  const shell = process.env.SHELL;
  if (!shell) return null;
  return SUPPORTED_SHELLS.find((s) => shell.endsWith(s));
}

function generateCompletion(shell) {
  switch (shell) {
    case "zsh":
      return `
#compdef ${NAME}

_${NAME}() {
  local -a dirs
  dirs=(\$(find . -type d -not -path '*/\\.*' 2>/dev/null))
  _describe 'directory' dirs
}

compdef _${NAME} ${NAME}
`;
    case "bash":
      return `
_${NAME}() {
  local cur=\${COMP_WORDS[COMP_CWORD]}
  local dirs=(\$(find . -type d -not -path '*/\\.*' 2>/dev/null))
  COMPREPLY=(\$(compgen -W "\${dirs[*]}" -- "\$cur"))
}

complete -F _${NAME} ${NAME}
`;
    case "fish":
      return `
function __fish_${NAME}_directories
  find . -type d -not -path '*/\\.*' 2>/dev/null
end

complete -c ${NAME} -a "(__fish_${NAME}_directories)"
`;
    default:
      throw new Error(`Unsupported shell: ${shell}`);
  }
}

const HELP_TEXT = `
Usage: ${NAME} [options] <directory-pattern>

A fuzzy directory search and navigation tool.

Options:
  \x1b[32m-h, --help\x1b[0m                Show this help message
  \x1b[32m--completion [shell]\x1b[0m      Generate shell completion script (bash, zsh, fish)
  \x1b[32m--init [shell]\x1b[0m            Generate shell initialization script (bash, zsh, fish)
  \x1b[32m-t, --threshold <number>\x1b[0m  Set minimum score threshold (default: 0)
  \x1b[32m-v, --verbose\x1b[0m             Enable verbose logging
  \x1b[32m--more\x1b[0m                    Show all matches without filtering
  \x1b[32m--first\x1b[0m                   Always go to the first match
  \x1b[32m--default-opts <options>\x1b[0m  Set default options for ${NAME} for shell init

Examples:
  \x1b[33m${NAME} proj\x1b[0m          # Fuzzy search for directories matching 'proj'
  \x1b[33m${NAME} web/src\x1b[0m       # Search for 'web' then 'src' within matches
  \x1b[33m${NAME} --threshold 5\x1b[0m # Only show matches with score >= 5
  \x1b[33m${NAME} --more\x1b[0m        # Show all matches without filtering
  \x1b[33m${NAME} --first\x1b[0m       # Always go to the first match

Shell Integration:
  To enable directory changing, you must add shell integration to your RC file.
`;

let SCORE_THRESHOLD = 10;
let SHOW_ALL_MATCHES = false;
let ALWAYS_FIRST_MATCH = false;

function findMatchesRecursively(startDirs, remainingParts, parentScore = 0) {
  log(
    `Recursive search with parts: ${remainingParts.join("/")}, parent score: ${parentScore}`,
  );

  if (remainingParts.length === 0) {
    return startDirs.filter((dir) => dir.score >= SCORE_THRESHOLD);
  }

  const currentPart = remainingParts[0];
  const nextParts = remainingParts.slice(1);
  let allMatches = [];

  for (const dir of startDirs) {
    let matches = closest(dir.path, currentPart);

    matches.forEach((match) => {
      match.score += parentScore;
      match.reasons.push({ why: "Parent score", amount: parentScore });
      const depthPenalty = Math.max(0, match.depth - 1) * 8;
      match.score -= depthPenalty;
      match.reasons.push({ why: "Depth penalty", amount: -depthPenalty });
      log(`Applied depth penalty -${depthPenalty} for ${match.path}`);
      match.fullScore = match.score;
    });

    if (matches.length > 0) {
      if (nextParts.length > 0) {
        const validMatches = matches.filter((m) => m.score >= SCORE_THRESHOLD);
        const deepMatches = findMatchesRecursively(
          validMatches,
          nextParts,
          parentScore,
        );
        allMatches = allMatches.concat(deepMatches);
      } else {
        allMatches = allMatches.concat(
          matches.filter((m) => m.score >= SCORE_THRESHOLD),
        );
      }
    }
  }

  return allMatches.sort((a, b) => b.score - a.score);
}
async function main() {
  const args = process.argv.slice(2);

  if (args.includes("-h") || args.includes("--help")) {
    console.log(HELP_TEXT);
    process.exit(0);
  }

  const defaultOptsIndex = args.findIndex((arg) => arg === "--default-opts" || arg === "-do");
  if (defaultOptsIndex !== -1) {
    DEFAULT_OPTS = args[defaultOptsIndex + 1];
    args.splice(defaultOptsIndex, 2);
  }

  const initIndex = args.findIndex((arg) => arg === "--init");
  if (initIndex !== -1) {
    const requestedShell = args[initIndex + 1] || getCurrentShell();
    if (!requestedShell || !SUPPORTED_SHELLS.includes(requestedShell)) {
      console.error(
        `\x1b[31mPlease specify a supported shell: ${SUPPORTED_SHELLS.join(", ")}\x1b[0m`,
      );
      process.exit(1);
    }
    try {
      console.log(generateInitScript(requestedShell));
      process.exit(0);
    } catch (error) {
      console.error(`\x1b[31m${error.message}\x1b[0m`);
      process.exit(1);
    }
  }

  const completionIndex = args.findIndex((arg) => arg === "--completion");
  if (completionIndex !== -1) {
    const requestedShell = args[completionIndex + 1] || getCurrentShell();
    if (!requestedShell || !SUPPORTED_SHELLS.includes(requestedShell)) {
      console.error(
        `\x1b[31mPlease specify a supported shell: ${SUPPORTED_SHELLS.join(", ")}\x1b[0m`,
      );
      process.exit(1);
    }
    try {
      console.log(generateCompletion(requestedShell));
      process.exit(0);
    } catch (error) {
      console.error(`\x1b[31m${error.message}\x1b[0m`);
      process.exit(1);
    }
  }

  const thresholdIndex = args.findIndex(
    (arg) => arg === "-t" || arg === "--threshold",
  );
  if (thresholdIndex !== -1) {
    const threshold = parseFloat(args[thresholdIndex + 1]);
    if (isNaN(threshold)) {
      console.error(`\x1b[31mInvalid threshold value\x1b[0m`);
      process.exit(1);
    }
    SCORE_THRESHOLD = threshold;
    args.splice(thresholdIndex, 2);
  }

  const verboseIndex = args.findIndex(
    (arg) => arg === "-v" || arg === "--verbose",
  );
  if (verboseIndex !== -1) {
    process.env.DEBUG = "true";
    args.splice(verboseIndex, 1);
  }

  if (args.includes("--more")) {
    SHOW_ALL_MATCHES = true;
    SCORE_THRESHOLD = 0;
    args.splice(args.indexOf("--more"), 1);
  }

  if (args.includes("--first")) {
    ALWAYS_FIRST_MATCH = true;
    args.splice(args.indexOf("--first"), 1);
  }

  const pattern = args[0];
  if (!pattern) {
    console.error(`\x1b[31mUsage: ${NAME} <directory-pattern>\x1b[0m`);
    console.error(`\x1b[31mUse --help for more information\x1b[0m`);
    process.exit(1);
  }

  log(`Starting search with pattern: ${pattern}`);

  const parts = pattern.split("/").filter((part) => part.length > 0);
  let currentDir = process.env.HOME || process.cwd();

  log(`Current directory: ${currentDir}`);
  log(`Path parts to process: ${parts.join(", ")}`);

  const initialMatches = searchUp(currentDir, parts[0]);

  if (initialMatches.length === 0) {
    console.error(`\x1b[31mNo matching directories found for "${parts[0]}"\x1b[0m`);
    process.exit(1);
  }

  let allMatches = findMatchesRecursively(initialMatches, parts.slice(1));

  allMatches = allMatches.map((i) => {
    let segs = i.path.split(path.sep);
    let cwdsegs = process.cwd().split(path.sep);
    let bonus = segs.reduce((acc, seg, idx) => {
      if (cwdsegs[idx] === seg) {
        return acc + 10;
      }
      return acc;
    }, 0);
    i.score += bonus;
    i.reasons.push({ why: "Path match bonus", amount: bonus });
    return i;
  });

  if (!SHOW_ALL_MATCHES) {
    if (allMatches.length > 1) {
      const RATIO = allMatches[1].score / allMatches[0].score;
      if (RATIO < 0.85) {
        allMatches = [allMatches[0]];
      }
    }
    allMatches = allMatches.map((i) => {
      let penalty = i.depth * 5;
      i.score -= penalty;
      i.reasons.push({ why: "Depth penalty", amount: -penalty });
      return i;
    });
    allMatches = allMatches.filter(
      (i) => i.score > Math.max(...allMatches.map((i) => i.score)) * 0.8,
    );
  }
  allMatches = allMatches.filter((i) => i.score > 40);
  allMatches
    .sort((a, b) => b.score - a.score)
    .map((i) => {
      i.reasons = i.reasons.sort((a, b) => b.amount - a.amount);
      return i;
    });

  if (allMatches.length === 0) {
    console.error(`\x1b[31mNo matching directories found\x1b[0m`);
    process.exit(1);
  }

  let selectedDir;
  if (allMatches.length === 1 || ALWAYS_FIRST_MATCH) {
    selectedDir = allMatches[0].path;
    log(`Single match found: ${selectedDir}`);
  } else {
    log(`Found ${allMatches.length} matching directories`);
    selectedDir = await selectWithFzf(allMatches);
    if (!selectedDir) {
      console.error(`\x1b[31mNo directory selected\x1b[0m`);

      process.exit(1);
    }
  }
  currentDir = selectedDir;
  log(`Selected directory: ${currentDir}`);

  log(`Final selected directory: ${currentDir}`);
  outputCdCommand(currentDir);
}

main().catch((error) => {
  console.error(`\x1b[31mError:\x1b[0m`, error);
  process.exit(1);
});
