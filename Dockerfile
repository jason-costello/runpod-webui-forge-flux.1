# When building an image for RunPod on a Mac (Apple Silicon), use the flag --platform linux/amd64
# to ensure your image is compatible with the platform. This flag is necessary because RunPod
# currently only supports the linux/amd64 architecture.
FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-devel AS base

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    SHELL=/bin/bash \
    MODEL_MOUNTPOINT=/workspace \
    MODEL="schnell" \
    HF="" \
    WEBUIPORT=7860 \
    ACCELERATE="True" \
    REQS_FILE="requirements_versions.txt" \
    LAUNCH_SCRIPT="launch.py" \
    GIT="git" \
    install_dir="/workspace/apps" \
    clone_dir="stable-diffusion-webui-forge" \
    LORAS=""

WORKDIR /workspace

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        git-lfs \
        wget \
        curl \
        bash \
        libgl1 \
        p7zip-full \
        software-properties-common \
        tree \
        libgoogle-perftools4 \
        libtcmalloc-minimal4 \
        openssh-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Set up Python and pip
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir huggingface_hub

# Create necessary directories
RUN mkdir -p /workspace/apps /workspace/models/VAE /workspace/models/text_encoder /workspace/models/Stable-diffusion /workspace/models/Loras

# Clone the Forge repository
RUN git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git /workspace/apps/stable-diffusion-webui-forge && \
    chmod +x /workspace/apps/stable-diffusion-webui-forge/webui.sh

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 7860

# Set the entrypoint
CMD ["/start.sh"]