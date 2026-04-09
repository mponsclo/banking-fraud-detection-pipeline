from fastapi import APIRouter, Request

from app.schemas import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health(request: Request):
    models = getattr(request.app.state, "models", {})
    return HealthResponse(status="ok", models_loaded=len(models))
