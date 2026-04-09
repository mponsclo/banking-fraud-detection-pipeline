"""Load serialized ML models at startup."""

import os
import joblib

MODELS_DIR = os.environ.get("MODELS_DIR", "outputs/models")


def load_models() -> dict:
    """Load fraud and forecast models from disk.

    Returns a dict with keys: fraud_model, forecast_h1, forecast_h2, forecast_h3,
    target_encodings, feature_metadata.
    """
    models = {}

    fraud_path = os.path.join(MODELS_DIR, "fraud_model.pkl")
    if os.path.exists(fraud_path):
        models["fraud_model"] = joblib.load(fraud_path)

    for h in [1, 2, 3]:
        path = os.path.join(MODELS_DIR, f"forecast_h{h}.pkl")
        if os.path.exists(path):
            models[f"forecast_h{h}"] = joblib.load(path)

    te_path = os.path.join(MODELS_DIR, "target_encodings.pkl")
    if os.path.exists(te_path):
        models["target_encodings"] = joblib.load(te_path)

    meta_path = os.path.join(MODELS_DIR, "feature_metadata.pkl")
    if os.path.exists(meta_path):
        models["feature_metadata"] = joblib.load(meta_path)

    print(f"Loaded {len(models)} model artifacts from {MODELS_DIR}")
    return models
