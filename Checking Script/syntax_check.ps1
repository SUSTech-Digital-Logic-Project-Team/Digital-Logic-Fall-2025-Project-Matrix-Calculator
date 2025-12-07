# Verilog Syntax Checker Script for PowerShell

# Get all Verilog files
$files = Get-ChildItem -Path $PSScriptRoot -Filter "*.v" -ErrorAction SilentlyContinue
$files += Get-ChildItem -Path $PSScriptRoot -Filter "*.vh" -ErrorAction SilentlyContinue

Write-Host "Verilog Syntax Checker" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green
Write-Host "Found $($files.Count) files to check`n"

$errors = @()
$warnings = @()

foreach ($file in $files) {
    Write-Host "Checking: $($file.Name)"
    
    $content = Get-Content -Path $file.FullName -Raw
    $lines = $content -split "`n"
    
    # Check module declarations
    $modules = [regex]::Matches($content, "^\s*module\s+(\w+)", "Multiline")
    $endmodules = [regex]::Matches($content, "^\s*endmodule\s*", "Multiline")
    
    if ($modules.Count -ne $endmodules.Count) {
        $errors += "$($file.Name): Module/endmodule mismatch (modules: $($modules.Count), endmodules: $($endmodules.Count))"
    } else {
        Write-Host "  ✓ Module declarations: $($modules.Count) module(s)"
    }
    
    # Check for balanced delimiters
    $openParens = [regex]::Matches($content, "\(").Count
    $closeParens = [regex]::Matches($content, "\)").Count
    $openBrackets = [regex]::Matches($content, "\[").Count
    $closeBrackets = [regex]::Matches($content, "\]").Count
    $openBraces = [regex]::Matches($content, "\{").Count
    $closeBraces = [regex]::Matches($content, "\}").Count
    
    if ($openParens -ne $closeParens) {
        $errors += "$($file.Name): Parenthesis mismatch (open: $openParens, close: $closeParens)"
    }
    if ($openBrackets -ne $closeBrackets) {
        $errors += "$($file.Name): Bracket mismatch (open: $openBrackets, close: $closeBrackets)"
    }
    if ($openBraces -ne $closeBraces) {
        $errors += "$($file.Name): Brace mismatch (open: $openBraces, close: $closeBraces)"
    }
    
    # Check port declarations
    $ports = [regex]::Matches($content, "^\s*(input|output|inout)", "Multiline")
    if ($ports.Count -gt 0) {
        Write-Host "  ✓ Port declarations: $($ports.Count) port(s)"
    }
    
    # Check for ram_style attribute in memory files
    if ($file.Name -like "*memory*" -or $file.Name -like "*bram*") {
        if ($content -match 'ram_style\s*=\s*"(block|distributed)"') {
            Write-Host "  ✓ RAM style attributes found (BRAM-compatible)"
        } else {
            $warnings += "$($file.Name): Memory file but no ram_style attribute"
        }
    }
    
    # Check timescale
    if ($content -match '`timescale') {
        Write-Host "  ✓ Timescale defined"
    } elseif ($file.Extension -eq ".v") {
        $warnings += "$($file.Name): No timescale defined"
    }
    
    Write-Host ""
}

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "SYNTAX CHECK RESULTS" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host "`n❌ ERRORS ($($errors.Count)):" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "  • $error" -ForegroundColor Red
    }
} else {
    Write-Host "`n✓ No errors found!" -ForegroundColor Green
}

if ($warnings.Count -gt 0) {
    Write-Host "`n⚠ WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  • $warning" -ForegroundColor Yellow
    }
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
if ($errors.Count -eq 0) {
    Write-Host "Status: PASS ✓ - Project ready for synthesis" -ForegroundColor Green
} else {
    Write-Host "Status: FAIL ✗ - Fix errors before synthesis" -ForegroundColor Red
}
Write-Host ("=" * 60) -ForegroundColor Cyan
