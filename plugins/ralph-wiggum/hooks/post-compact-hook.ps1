# Ralph Wiggum Post-Compact Hook
# Re-injects the full Ralph prompt after context compaction
# Since compaction frees up context, we can inject the full prompt here

$ErrorActionPreference = "Stop"

$RalphStateFile = ".claude/ralph-loop.local.md"

if (-not (Test-Path $RalphStateFile)) {
    # No active Ralph loop - do nothing
    exit 0
}

# Read full state file
$Content = Get-Content $RalphStateFile -Raw

# Parse frontmatter for metadata
if ($Content -match 'iteration:\s*(\d+)') {
    $Iteration = $Matches[1]
} else {
    # No valid iteration found, skip
    exit 0
}

if ($Content -match 'max_iterations:\s*(\d+)') {
    $MaxIterations = [int]$Matches[1]
} else {
    $MaxIterations = 0
}

if ($Content -match 'completion_promise:\s*"([^"]*)"') {
    $CompletionPromise = $Matches[1]
} else {
    $CompletionPromise = $null
}

# Extract the full prompt (everything after closing ---)
if ($Content -match '(?s)^---.*?\n---\s*\n(.*)$') {
    $PromptText = $Matches[1].Trim()
} else {
    # No prompt found, skip
    exit 0
}

# Build context message with FULL PROMPT (we have fresh context after compaction)
if ($CompletionPromise) {
    $PromiseInfo = "To complete this loop, output: <promise>$CompletionPromise</promise> (ONLY when TRUE - do not lie!)"
} else {
    $PromiseInfo = "No completion promise set - loop runs indefinitely."
}

$MaxIterInfo = if ($MaxIterations -gt 0) { "Max iterations: $MaxIterations" } else { "Max iterations: unlimited" }

$AdditionalContext = @"
Ralph Wiggum loop resuming after context compaction (iteration $Iteration).

$MaxIterInfo
$PromiseInfo

=== TASK ===
$PromptText
"@

$Response = @{
    hookSpecificOutput = @{
        hookEventName = "SessionStart"
        additionalContext = $AdditionalContext
    }
} | ConvertTo-Json -Compress

Write-Output $Response
exit 0
