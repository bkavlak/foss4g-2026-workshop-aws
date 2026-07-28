# syntax=docker/dockerfile:1

# Participant environment: GDAL and Python in one image.
#
# The base image is chosen for a specific reason: GDAL 3.13's ubuntu-small
# variant is built on Ubuntu 26.04, whose system interpreter is Python 3.14 and
# whose osgeo bindings are compiled against it. Using it means GDAL and the
# required Python version come from one place instead of being reconciled by
# hand.
#
# The image intentionally carries no workshop data. The dataset is ~20 GB and
# is synced into /data at pod start from S3, which keeps this image small
# enough to pull in under a minute on a cold node and lets the data change
# without a rebuild.
FROM ghcr.io/osgeo/gdal:ubuntu-small-3.13.2

ARG NB_USER=jovyan
ARG NB_UID=1000
ARG VENV=/opt/venv

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Participants get the dataset here; the path is part of the workshop
    # contract and is referenced by the Helm chart.
    WORKSHOP_DATA=/data

# hadolint ignore=DL3008,DL3009
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        less \
        python3-venv \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.11.32 /uv /usr/local/bin/uv

# A virtualenv with --system-site-packages rather than installing into the
# system interpreter: the base image's osgeo bindings live in dist-packages and
# stay visible, while nothing here fights Ubuntu's externally-managed marker.
#
# Note for anyone debugging a version mismatch: `from osgeo import gdal` reports
# the image's GDAL 3.13.2, but rasterio and pyogrio ship their own bundled GDAL
# in their wheels and will report a different version. Both work; they are
# simply not the same library.
RUN python3 -m venv --system-site-packages ${VENV}
ENV PATH="${VENV}/bin:${PATH}" \
    VIRTUAL_ENV="${VENV}"

COPY requirements.txt /tmp/requirements.txt
RUN uv pip install --python ${VENV}/bin/python --no-cache -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

RUN useradd --create-home --uid ${NB_UID} --shell /bin/bash ${NB_USER} \
    && mkdir -p ${WORKSHOP_DATA} \
    && chown ${NB_USER}:${NB_USER} ${WORKSHOP_DATA}

USER ${NB_UID}
WORKDIR /home/${NB_USER}

# A cheap guarantee that the two halves of this image actually coexist. It
# fails the build rather than a participant's first cell.
RUN python -c "from osgeo import gdal; import geopandas, rasterio; print(gdal.__version__)"

# tini reaps the kernels JupyterLab spawns; without it a pod accumulates
# zombies across a day-long workshop.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["jupyterhub-singleuser"]
