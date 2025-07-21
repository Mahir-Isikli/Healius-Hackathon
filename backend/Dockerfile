# ---------- GPU base ----------
    FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

    # ---------- env ----------
    ENV DEBIAN_FRONTEND=noninteractive
    ENV PYTHONUNBUFFERED=1
    ENV CUDA_VISIBLE_DEVICES=0
    
    # ---------- system deps ----------
    RUN apt-get update && apt-get install -y --no-install-recommends \
            python3.10 python3.10-dev python3-pip \
            wget git curl \
            libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
            libgomp1 ffmpeg \
            libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavdevice-dev \
            ### NEW — aiortc native build + WebRTC codecs
            libopus-dev libvpx-dev libsrtp2-dev pkg-config build-essential \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
    
    # ---------- workdir ----------
    WORKDIR /app
    
    # ---------- Python deps ----------
    COPY pyproject.toml .
    COPY requirements.txt .
    RUN pip3 install --no-cache-dir -r requirements.txt
    
    # Torch + CUDA 11.8 wheels
    RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
    
    # ---------- copy app ----------
    COPY . .
    
    # ---------- warm-up HF weights (optional) ----------
RUN python3 -c "from transformers import AutoProcessor, VitPoseForPoseEstimation; AutoProcessor.from_pretrained('usyd-community/vitpose-base-simple'); VitPoseForPoseEstimation.from_pretrained('usyd-community/vitpose-base-simple')"
    
    # ---------- ports & health ----------
    EXPOSE 8000
    HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
        CMD curl -f http://localhost:8000/gpu-check || exit 1
    
    # ---------- launch ----------
    CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
    