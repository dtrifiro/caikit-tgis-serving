#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if ! command -v docker-compose &>/dev/null; then
	echo "This requires docker-compose" 2>&1
	exit 1
fi

if [[ -z $CI && -z $VIRTUAL_ENV ]]; then
	echo "This script installs caikit-nlp-client with pip. Please run in a virtualenv" >&2
	exit 1
fi

cd "$SCRIPT_DIR"
mkdir -p models

docker-compose build

if [[ ! -d ${SCRIPT_DIR}/models/flan-t5-small-caikit ]]; then
	# use the container's environment to convert the model to caikit format
	docker run --user root \
		-e "ALLOW_DOWNLOADS=1" \
		-v ./caikit_config:/caikit/config/ \
		-v ./../../utils:/utils \
		-v ./models/:/mnt/models quay.io/opendatahub/caikit-tgis-serving:dev \
		/utils/convert.py --model-path "google/flan-t5-small" --model-save-path /mnt/models/flan-t5-small-caikit/
	echo "Saved caikit model to ${SCRIPT_DIR}/models/"
fi

if [[ -n $CI ]]; then # Free up some space on CI
	rm -rf ~/.cache/huggingface
fi

docker-compose up -d

pip install caikit-nlp-client

echo -e "\n=== Testing endpoints..."
if ! python ../smoke-test.py; then
	echo -e "\n=== Container logs"
	docker-compose logs
	echo -e "\n=== 👎 Test failed\n"
	docker-compose down
	exit 1
fi

echo -e "\n=== 👍 Test successful!\n"
cd ${SCRIPT_DIR} && docker-compose down
