param()

# ─── GPU Profile Selection ───
if (-not $env:GPU_PROFILE_TYPE) {
    Write-Host ""
    Write-Host "Select GPU profile:"
    Write-Host "  1) T4  (16 GB VRAM) - good for smaller Gemma4 models (e2b, e4b, 12b)"
    Write-Host "  2) A100 (80 GB VRAM) - supports all Gemma4 models including 12b, 26b and 31b"
    Write-Host ""
    $gpuChoice = Read-Host "Enter choice [1/2] (default: 1)"
    if ([string]::IsNullOrWhiteSpace($gpuChoice)) { $gpuChoice = "1" }

    switch ($gpuChoice) {
        "2" { $gpuProfile = "Consumption-GPU-NC24-A100" }
        default { $gpuProfile = "Consumption-GPU-NC8as-T4" }
    }

    azd env set GPU_PROFILE_TYPE $gpuProfile | Out-Null
    azd env config set infra.parameters.gpuProfileType $gpuProfile 2>$null
    $env:GPU_PROFILE_TYPE = $gpuProfile
}

# ─── Model Selection (based on GPU) ───
if (-not $env:MODEL_ID) {
    Write-Host ""
    if ($env:GPU_PROFILE_TYPE -eq "Consumption-GPU-NC24-A100") {
        Write-Host "Select Gemma 4 model for A100:"
        Write-Host "  1) gemma4:e4b   - 4B params, fast, multimodal (text+image+audio)"
        Write-Host "  2) gemma4:26b   - 26B MoE, strong reasoning, 256K context"
        Write-Host "  3) gemma4:31b   - 31B dense, highest quality, 256K context"
        Write-Host "  4) gemma4:12b   - 12B dense, near-26B reasoning at half the memory, native audio"
        Write-Host "  5) gemma4:e2b   - 2B params, ultra-fast, multimodal"
        Write-Host ""
        $modelChoice = Read-Host "Enter choice [1-5] (default: 2)"
        if ([string]::IsNullOrWhiteSpace($modelChoice)) { $modelChoice = "2" }

        switch ($modelChoice) {
            "1" { $modelId = "google/gemma-4n-e4b-it"; $servedName = "gemma4:e4b" }
            "3" { $modelId = "google/gemma-4-31b-it"; $servedName = "gemma4:31b" }
            "4" { $modelId = "google/gemma-4-12b-it"; $servedName = "gemma4:12b" }
            "5" { $modelId = "google/gemma-4n-e2b-it"; $servedName = "gemma4:e2b" }
            default { $modelId = "google/gemma-4-26B-A4B-it"; $servedName = "gemma4:26b" }
        }
    }
    else {
        Write-Host "Select Gemma 4 model for T4:"
        Write-Host "  1) gemma4:e4b   - 4B params, good balance of speed and quality"
        Write-Host "  2) gemma4:e2b   - 2B params, fastest, best for simple tasks"
        Write-Host "  3) gemma4:12b   - 12B dense, laptop-class reasoning (~1/2 throughput of e4b on T4)"
        Write-Host ""
        $modelChoice = Read-Host "Enter choice [1-3] (default: 1)"
        if ([string]::IsNullOrWhiteSpace($modelChoice)) { $modelChoice = "1" }

        switch ($modelChoice) {
            "2" { $modelId = "google/gemma-4n-e2b-it"; $servedName = "gemma4:e2b" }
            "3" { $modelId = "google/gemma-4-12b-it"; $servedName = "gemma4:12b" }
            default { $modelId = "google/gemma-4n-e4b-it"; $servedName = "gemma4:e4b" }
        }
    }

    azd env set MODEL_ID $modelId | Out-Null
    azd env config set infra.parameters.modelId $modelId 2>$null
    azd env set SERVED_MODEL_NAME $servedName | Out-Null
    azd env config set infra.parameters.servedModelName $servedName 2>$null
    $env:MODEL_ID = $modelId
    $env:SERVED_MODEL_NAME = $servedName
}

# ─── Hugging Face Token (required for gated Gemma weights) ───
if (-not $env:HUGGING_FACE_TOKEN) {
    Write-Host ""
    Write-Host "Gemma model weights are gated on Hugging Face and require an access token."
    Write-Host "Create one at: https://huggingface.co/settings/tokens (read access is sufficient)"
    Write-Host ""
    $hfToken = Read-Host "Enter your Hugging Face access token" -AsSecureString
    $hfTokenPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($hfToken))

    if ($hfTokenPlain) {
        azd env set HUGGING_FACE_TOKEN $hfTokenPlain | Out-Null
        $env:HUGGING_FACE_TOKEN = $hfTokenPlain
    }
}

Write-Host ""
Write-Host "Configuration:"
Write-Host "  GPU Profile : $env:GPU_PROFILE_TYPE"
Write-Host "  Model       : $env:SERVED_MODEL_NAME ($env:MODEL_ID)"
Write-Host ""

