#!/usr/bin/env bash
# Compile transaction.proto and copy the generated Python module
# to both Cloud Function directories.
#
# Usage: ./proto/generate.sh
# Requires: pip install grpcio-tools

set -euo pipefail

PROTO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$PROTO_DIR")"

echo "Compiling ${PROTO_DIR}/transaction.proto ..."
python3 -m grpc_tools.protoc \
    --proto_path="$PROTO_DIR" \
    --python_out="$PROTO_DIR" \
    "$PROTO_DIR/transaction.proto"

echo "Copying transaction_pb2.py to function directories ..."
cp "$PROTO_DIR/transaction_pb2.py" "$REPO_ROOT/functions/producer/"
cp "$PROTO_DIR/transaction_pb2.py" "$REPO_ROOT/functions/consumer/"

echo "Done."
