#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #
execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash "${script_path}"
    fi
}

setup_ssh() {
    if [[ -n ${PUBLIC_KEY:-} ]]; then
        echo "Setting up SSH..."
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 ~/.ssh
        chmod 600 ~/.ssh/authorized_keys

        for key_type in rsa dsa ecdsa ed25519; do
            local key_file="/etc/ssh/ssh_host_${key_type}_key"
            [[ -f $key_file ]] || ssh-keygen -t "$key_type" -f "$key_file" -q -N ''
        done

        service ssh start

        echo "SSH host keys:"
        cat /etc/ssh/*.pub
    fi
}

export_envvars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^RUNPOD|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

start_forge() {
    cd /workspace/apps/stable-diffusion-webui-forge || exit
    bash webui.sh -f --share
}

download_models() {
    echo "Checking and downloading model weights if necessary..."
    local model_dirs=("VAE" "text_encoder" "Stable-diffusion")
    for dir in "${model_dirs[@]}"; do
        mkdir -p "/workspace/models/$dir"
    done

    local -A model_files=(
        ["schnell"]="flux1-schnell.safetensors"
        ["dev"]="flux1-dev.safetensors"
    )

    local model_type=${MODEL:-schnell}
    model_type=${model_type,,}  # Convert to lowercase
    local model_file=${model_files[$model_type]:-${model_files["schnell"]}}

    local files_to_download=(
        "Stable-diffusion/$model_file|https://huggingface.co/black-forest-labs/FLUX.1-$model_type/resolve/main/$model_file"
        "VAE/vae.safetensors|https://huggingface.co/black-forest-labs/FLUX.1-$model_type/resolve/main/ae.safetensors"
        "text_encoder/t5xxl_fp16.safetensors|https://huggingface.co/lllyasviel/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
        "text_encoder/clip_l.safetensors|https://huggingface.co/lllyasviel/flux_text_encoders/resolve/main/clip_l.safetensors"
    )

    for file in "${files_to_download[@]}"; do
        IFS="|" read -r local_path url <<< "$file"
        full_path="/workspace/models/$local_path"
        if [[ ! -f "$full_path" ]]; then
            echo "Downloading $local_path..."
            wget --header="Authorization: Bearer $HF" -O "$full_path" "${url}?download=true"
        else
            echo "$local_path already exists, skipping download."
        fi
    done
    echo "Model weight check and download completed!"
}

create_model_symlinks() {
    echo "Creating symlinks for downloaded models..."
    local sd_webui_path="/workspace/apps/stable-diffusion-webui-forge/models"
    local central_models_path="/workspace/models"
    
    mkdir -p "$sd_webui_path"/{VAE,Stable-diffusion}
    
    ln -sf "$central_models_path/VAE/vae.safetensors" "$sd_webui_path/VAE/vae.safetensors"
    
    local model_type=${MODEL:-schnell}
    model_type=${model_type,,}
    ln -sf "$central_models_path/Stable-diffusion/flux1-$model_type.safetensors" "$sd_webui_path/Stable-diffusion/flux1-$model_type.safetensors"
    
    echo "Symlinks created successfully!"
}

download_loras() {
    if [[ -n ${LORAS:-} ]]; then
        echo "Downloading Lora files..."
        mkdir -p /workspace/models/Loras
        IFS=',' read -ra LORA_URLS <<< "$LORAS"
        for url in "${LORA_URLS[@]}"; do
            filename=$(basename "$url")
            echo "Downloading $filename..."
            if wget --header="Authorization: Bearer $HF" -q -O "/workspace/models/Loras/$filename" "$url"; then
                echo "Successfully downloaded $filename"
            else
                echo "Failed to download $filename"
            fi
        done
    else
        echo "No Lora files specified for download."
    fi
}

create_lora_symlinks() {
    echo "Creating symlinks for Lora files..."
    mkdir -p /workspace/apps/stable-diffusion-webui-forge/models/Loras
    find /workspace/models/Loras -type f -print0 | 
        while IFS= read -r -d '' file; do
            ln -sf "$file" "/workspace/apps/stable-diffusion-webui-forge/models/Loras/$(basename "$file")"
        done
    echo "Lora symlinks created successfully!"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #
main() {
    execute_script "/pre_start.sh" "Running pre-start script..."
    setup_ssh
    export_envvars
    download_models
    create_model_symlinks
    download_loras
    create_lora_symlinks
    start_forge
    execute_script "/post_start.sh" "Running post-start script..."
    echo "Start script(s) finished, pod is ready to use."
    sleep infinity
}

main