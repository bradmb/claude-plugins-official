# Ralph Wiggum Stop Hook
# Prevents session exit when a ralph-loop is active
# Feeds Claude's output back as input to continue the loop

$ErrorActionPreference = "Stop"

# Read hook input from stdin (advanced stop hook API)
$HookInput = $input | Out-String

# Check if ralph-loop is active
$RalphStateFile = ".claude/ralph-loop.local.md"

if (-not (Test-Path $RalphStateFile)) {
    # No active loop - allow exit
    exit 0
}

# Parse markdown frontmatter (YAML between ---) and extract values
$Content = Get-Content $RalphStateFile -Raw
if ($Content -match '(?s)^---\s*\n(.*?)\n---') {
    $Frontmatter = $Matches[1]
} else {
    Write-Error "⚠️  Ralph loop: State file corrupted - no frontmatter found"
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Extract values from frontmatter
if ($Frontmatter -match 'iteration:\s*(\d+)') {
    $Iteration = [int]$Matches[1]
} else {
    Write-Error @"
⚠️  Ralph loop: State file corrupted
   File: $RalphStateFile
   Problem: 'iteration' field is not a valid number

   This usually means the state file was manually edited or corrupted.
   Ralph loop is stopping. Run /ralph-loop again to start fresh.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

if ($Frontmatter -match 'max_iterations:\s*(\d+)') {
    $MaxIterations = [int]$Matches[1]
} else {
    Write-Error @"
⚠️  Ralph loop: State file corrupted
   File: $RalphStateFile
   Problem: 'max_iterations' field is not a valid number

   This usually means the state file was manually edited or corrupted.
   Ralph loop is stopping. Run /ralph-loop again to start fresh.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Extract completion_promise (may be quoted or null)
if ($Frontmatter -match 'completion_promise:\s*"([^"]*)"') {
    $CompletionPromise = $Matches[1]
} elseif ($Frontmatter -match 'completion_promise:\s*null') {
    $CompletionPromise = "null"
} else {
    $CompletionPromise = "null"
}

# Check if max iterations reached
if ($MaxIterations -gt 0 -and $Iteration -ge $MaxIterations) {
    Write-Output "🛑 Ralph loop: Max iterations ($MaxIterations) reached."
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Get transcript path from hook input
try {
    $HookData = $HookInput | ConvertFrom-Json
    $TranscriptPath = $HookData.transcript_path
} catch {
    Write-Error "⚠️  Ralph loop: Failed to parse hook input JSON"
    Remove-Item $RalphStateFile -Force
    exit 0
}

if (-not (Test-Path $TranscriptPath)) {
    Write-Error @"
⚠️  Ralph loop: Transcript file not found
   Expected: $TranscriptPath
   This is unusual and may indicate a Claude Code internal issue.
   Ralph loop is stopping.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Read last assistant message from transcript (JSONL format - one JSON per line)
$TranscriptLines = Get-Content $TranscriptPath
$AssistantLines = $TranscriptLines | Where-Object { $_ -match '"role":"assistant"' }

if ($AssistantLines.Count -eq 0) {
    Write-Error @"
⚠️  Ralph loop: No assistant messages found in transcript
   Transcript: $TranscriptPath
   This is unusual and may indicate a transcript format issue
   Ralph loop is stopping.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Get last assistant message
$LastLine = $AssistantLines[-1]

try {
    $LastMessage = $LastLine | ConvertFrom-Json
    $TextContent = $LastMessage.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }
    $LastOutput = $TextContent -join "`n"
} catch {
    Write-Error @"
⚠️  Ralph loop: Failed to parse assistant message JSON
   Error: $_
   This may indicate a transcript format issue
   Ralph loop is stopping.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

if ([string]::IsNullOrWhiteSpace($LastOutput)) {
    Write-Error @"
⚠️  Ralph loop: Assistant message contained no text content
   Ralph loop is stopping.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Check for completion promise (only if set)
if ($CompletionPromise -ne "null" -and ![string]::IsNullOrEmpty($CompletionPromise)) {
    # Extract text from <promise> tags
    if ($LastOutput -match '<promise>\s*(.*?)\s*</promise>') {
        $PromiseText = $Matches[1].Trim()
        
        # Use exact string comparison
        if ($PromiseText -eq $CompletionPromise) {
            Write-Output "✅ Ralph loop: Detected <promise>$CompletionPromise</promise>"
            Remove-Item $RalphStateFile -Force
            exit 0
        }
    }
}

# Not complete - continue loop with SAME PROMPT
$NextIteration = $Iteration + 1

# Extract prompt (everything after the closing ---)
if ($Content -match '(?s)^---.*?\n---\s*\n(.*)$') {
    $PromptText = $Matches[1].Trim()
} else {
    Write-Error @"
⚠️  Ralph loop: State file corrupted or incomplete
   File: $RalphStateFile
   Problem: No prompt text found

   This usually means:
     • State file was manually edited
     • File was corrupted during writing

   Ralph loop is stopping. Run /ralph-loop again to start fresh.
"@
    Remove-Item $RalphStateFile -Force
    exit 0
}

# Update iteration in frontmatter
$UpdatedContent = $Content -replace '(?m)^iteration:\s*\d+', "iteration: $NextIteration"
$UpdatedContent | Set-Content -Path $RalphStateFile -NoNewline

# Build system message with iteration count and completion promise info
if ($CompletionPromise -ne "null" -and ![string]::IsNullOrEmpty($CompletionPromise)) {
    $SystemMsg = "🔄 Ralph iteration $NextIteration | To stop: output <promise>$CompletionPromise</promise> (ONLY when statement is TRUE - do not lie to exit!)"
} else {
    $SystemMsg = "🔄 Ralph iteration $NextIteration | No completion promise set - loop runs infinitely"
}

# Output JSON to block the stop and feed prompt back
$Response = @{
    decision = "block"
    reason = $PromptText
    systemMessage = $SystemMsg
} | ConvertTo-Json -Compress

Write-Output $Response

# Exit 0 for successful hook execution
exit 0
