"""Testes rápidos do handler, sem Docker: python -m pytest tests/ (ou python tests/test_handler.py)."""
import json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "hello_world"))
import app  # noqa: E402

RAIZ = os.path.join(os.path.dirname(__file__), "..")


def test_evento_gerado_pelo_sam_base64():
    with open(os.path.join(RAIZ, "events", "pedido.json")) as f:
        evento = json.load(f)
    r = app.lambda_handler(evento, None)
    assert r["statusCode"] == 201
    corpo = json.loads(r["body"])
    assert corpo["guia"] == "G-R-001"
    assert corpo["hospital"] == "H-Recife"
    assert corpo["bolsas"] == ["O-NEG-0142"]


def test_body_texto_puro_como_no_start_api():
    r = app.lambda_handler({"body": json.dumps({"requisicaoId": "R-002", "hospital": "H-Caruaru"})}, None)
    assert r["statusCode"] == 201
    assert json.loads(r["body"])["bolsas"] == []


def test_sem_requisicao_id_retorna_400():
    r = app.lambda_handler({"body": "{}"}, None)
    assert r["statusCode"] == 400


def test_contador_cresce_no_mesmo_processo():
    antes = app.contador
    app.lambda_handler({"body": json.dumps({"requisicaoId": "X"})}, None)
    assert app.contador == antes + 1


if __name__ == "__main__":
    for nome, fn in list(globals().items()):
        if nome.startswith("test_"):
            fn()
            print("ok", nome)
