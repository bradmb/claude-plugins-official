# Ralph Loop Setup Script
# Creates state file for in-session Ralph loop

param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# Parse arguments
$PromptParts = @()
$MaxIterations = 0
$CompletionPromise = "null"

$i = 0
while ($i -lt $RemainingArgs.Count) {
    switch ($RemainingArgs[$i]) {
        { $_ -in '-h', '--help' } {
            @"
Ralph Loop - Interactive self-referential development loop

USAGE:
  /ralph-loop [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: unlimited)
  --completion-promise '<text>'  Promise phrase (USE QUOTES for multi-word)
  -h, --help                     Show this help message

DESCRIPTION:
  Starts a Ralph Wiggum loop in your CURRENT session. The stop hook prevents
  exit and feeds your output back as input until completion or iteration limit.

  To signal completion, you must output: <promise>YOUR_PHRASE</promise>

  Use this for:
  - Interactive iteration where you want to see progress
  - Tasks requiring self-correction and refinement
  - Learning how Ralph works

EXAMPLES:
  /ralph-loop Build a todo API --completion-promise 'DONE' --max-iterations 20
  /ralph-loop --max-iterations 10 Fix the auth bug
  /ralph-loop Refactor cache layer  (runs forever)
  /ralph-loop --completion-promise 'TASK COMPLETE' Create a REST API

STOPPING:
  Only by reaching --max-iterations or detecting --completion-promise
  No manual stop - Ralph runs infinitely by default!

MONITORING:
  # View current iteration:
  Select-String -Path .claude/ralph-loop.local.md -Pattern '^iteration:'

  # View full state:
  Get-Content .claude/ralph-loop.local.md -TotalCount 10
"@
            exit 0
        }
        '--max-iterations' {
            if ($i + 1 -ge $RemainingArgs.Count -or [string]::IsNullOrEmpty($RemainingArgs[$i + 1])) {
                Write-Error @"
❌ Error: --max-iterations requires a number argument

   Valid examples:
     --max-iterations 10
     --max-iterations 50
     --max-iterations 0  (unlimited)

   You provided: --max-iterations (with no number)
"@
                exit 1
            }
            $i++
            if ($RemainingArgs[$i] -notmatch '^\d+$') {
                Write-Error @"
❌ Error: --max-iterations must be a positive integer or 0, got: $($RemainingArgs[$i])

   Valid examples:
     --max-iterations 10
     --max-iterations 50
     --max-iterations 0  (unlimited)

   Invalid: decimals (10.5), negative numbers (-5), text
"@
                exit 1
            }
            $MaxIterations = [int]$RemainingArgs[$i]
            $i++
        }
        '--completion-promise' {
            if ($i + 1 -ge $RemainingArgs.Count -or [string]::IsNullOrEmpty($RemainingArgs[$i + 1])) {
                Write-Error @"
❌ Error: --completion-promise requires a text argument

   Valid examples:
     --completion-promise 'DONE'
     --completion-promise 'TASK COMPLETE'
     --completion-promise 'All tests passing'

   You provided: --completion-promise (with no text)

   Note: Multi-word promises must be quoted!
"@
                exit 1
            }
            $i++
            $CompletionPromise = $RemainingArgs[$i]
            $i++
        }
        default {
            # Non-option argument - collect as prompt part
            $PromptParts += $RemainingArgs[$i]
            $i++
        }
    }
}

# Join all prompt parts with spaces
$Prompt = $PromptParts -join ' '

# Validate prompt is non-empty
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Error @"
❌ Error: No prompt provided

   Ralph needs a task description to work on.

   Examples:
     /ralph-loop Build a REST API for todos
     /ralph-loop Fix the auth bug --max-iterations 20
     /ralph-loop --completion-promise 'DONE' Refactor code

   For all options: /ralph-loop --help
"@
    exit 1
}

# Create state file for stop hook (markdown with YAML frontmatter)
New-Item -ItemType Directory -Path ".claude" -Force | Out-Null

# Quote completion promise for YAML if it contains special chars or is not null
if (![string]::IsNullOrEmpty($CompletionPromise) -and $CompletionPromise -ne "null") {
    $CompletionPromiseYaml = "`"$CompletionPromise`""
} else {
    $CompletionPromiseYaml = "null"
}

$StartedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$StateContent = @"
---
active: true
iteration: 1
max_iterations: $MaxIterations
completion_promise: $CompletionPromiseYaml
started_at: "$StartedAt"
---

$Prompt
"@

$StateContent | Set-Content -Path ".claude/ralph-loop.local.md" -NoNewline

# Output setup message
$MaxIterDisplay = if ($MaxIterations -gt 0) { $MaxIterations } else { "unlimited" }
$PromiseDisplay = if ($CompletionPromise -ne "null") { "$CompletionPromise (ONLY output when TRUE - do not lie!)" } else { "none (runs forever)" }

Write-Output @"
🔄 Ralph loop activated in this session!

Iteration: 1
Max iterations: $MaxIterDisplay
Completion promise: $PromiseDisplay

The stop hook is now active. When you try to exit, the SAME PROMPT will be
fed back to you. You'll see your previous work in files, creating a
self-referential loop where you iteratively improve on the same task.

To monitor: Get-Content .claude/ralph-loop.local.md -TotalCount 10

⚠️  WARNING: This loop cannot be stopped manually! It will run infinitely
    unless you set --max-iterations or --completion-promise.

🔄
"@

# Output the initial prompt if provided
if (![string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Output ""
    Write-Output $Prompt
}

# Display completion promise requirements if set
if ($CompletionPromise -ne "null") {
    Write-Output @"

═══════════════════════════════════════════════════════════
CRITICAL - Ralph Loop Completion Promise
═══════════════════════════════════════════════════════════

To complete this loop, output this EXACT text:
  <promise>$CompletionPromise</promise>

STRICT REQUIREMENTS (DO NOT VIOLATE):
  ✓ Use <promise> XML tags EXACTLY as shown above
  ✓ The statement MUST be completely and unequivocally TRUE
  ✓ Do NOT output false statements to exit the loop
  ✓ Do NOT lie even if you think you should exit

IMPORTANT - Do not circumvent the loop:
  Even if you believe you're stuck, the task is impossible,
  or you've been running too long - you MUST NOT output a
  false promise statement. The loop is designed to continue
  until the promise is GENUINELY TRUE. Trust the process.

  If the loop should stop, the promise statement will become
  true naturally. Do not force it by lying.
═══════════════════════════════════════════════════════════
"@
}
