param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

& (Join-Path $PSScriptRoot "run-regulation-tests.ps1") -Suite "ci-selection" @Args
exit $LASTEXITCODE
