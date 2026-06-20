param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

& (Join-Path $PSScriptRoot "run-regulation-tests.ps1") -Suite "orchestrator" @Args
exit $LASTEXITCODE
