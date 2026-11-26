# Rota Vital · Função serverless de guia de transporte

Atividade individual 1 (Serverless), Infraestrutura de Software, ADS, CESAR School, 2026.2.

Uma função (AWS Lambda, Python 3.12) recebe uma requisição do Rota Vital e devolve a guia de transporte. Ela pode ser acionada por **evento** (`sam local invoke`) e por **HTTP** (`sam local start-api` + `curl`).

**Caminho escolhido: A (AWS SAM CLI local)**, sem conta na AWS.

## Estrutura

```
template.yaml          # função, rota POST /guias, Timeout e memória (Globals)
hello_world/app.py     # handler
events/pedido.json     # evento do API Gateway gerado pelo SAM (Passo 3)
tests/test_handler.py  # testes do handler sem Docker
roteiro.sh             # roda os Passos 3, 4 e 5 e salva as saídas em evidencias/
evidencias/            # prints e saídas dos comandos
```

## Pré-requisitos

- Docker Desktop aberto
- AWS SAM CLI (`sam --version`)
- Python 3.12
- No Windows: Git Bash ou WSL

## Como rodar

### Passo 3: invocação com evento

```bash
# (o events/pedido.json já está no repositório; para gerar de novo:)
sam local generate-event apigateway aws-proxy --method POST --path guias \
  --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' > events/pedido.json

sam build            # se o Python da máquina não for 3.12: sam build --use-container
sam local invoke -e events/pedido.json   # rodar duas vezes
# ou: ./roteiro.sh invoke   (faz as duas com `time` e salva em evidencias/)
```

### Passo 4: acionamento por HTTP

```bash
# terminal 1
sam local start-api
# terminal 2 (três vezes)
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
# ou: ./roteiro.sh curl sem-warm

# depois: parar o terminal 1 (Ctrl+C) e subir com reaproveitamento
sam local start-api --warm-containers LAZY
./roteiro.sh curl lazy
```

### Passo 5: limite de tempo

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-003","demorar":true}'
# ou: ./roteiro.sh timeout 3s

# trocar Timeout: 3 -> 10 em Globals no template.yaml, depois:
sam build
sam local start-api
./roteiro.sh timeout 10s
```

### Testes do handler (sem Docker)

```bash
python tests/test_handler.py
```

## Ajuste no código do enunciado

O `sam local generate-event` gera o evento com `"isBase64Encoded": true` e o `body` em base64. O código original fazia `json.loads(event["body"])` direto, o que dá `JSONDecodeError` no Passo 3. Acrescentei a decodificação:

```python
body = event.get("body") or "{}"
if event.get("isBase64Encoded"):
    body = base64.b64decode(body).decode("utf-8")
pedido = json.loads(body)
```

No `start-api` + `curl`, o body chega como texto (`isBase64Encoded: false`), então os dois caminhos funcionam.

## Resultados observados

Executado no GitHub Codespaces (Linux, Docker 29.9, SAM CLI 1.174.1). Como o Python do Codespace é 3.14 e a função usa o runtime 3.12, o build foi feito com `sam build --use-container`.

| Experimento | Resultado |
|---|---|
| `sam local invoke` – 1ª invocação | 201, `Duration: 55.74 ms`, tempo total **19,3 s** (inclui baixar a imagem `public.ecr.aws/lambda/python:3.12-rapid`) |
| `sam local invoke` – 2ª invocação | 201, `Duration: 49.23 ms`, tempo total **4,4 s** (imagem já em cache) |
| `start-api` sem warm – `invocacaoNesteAmbiente` | **1, 1, 1** (1,50 s / 0,65 s / 0,61 s) |
| `start-api --warm-containers LAZY` – `invocacaoNesteAmbiente` | **1, 2, 3** (0,77 s / 0,03 s / 0,03 s) |
| `demorar=true` com Timeout 3 | `HTTP/1.1 502 BAD GATEWAY`, body `{"message":"Internal server error"}`; log do SAM: `Function 'HelloWorldFunction' timed out after 3 seconds` |
| `demorar=true` com Timeout 10 | `HTTP/1.1 201 CREATED`, guia `G-R-003`, ~5,8 s |

Print do resumo: [`evidencias/resumo-execucao.jpg`](evidencias/resumo-execucao.jpg).

## Respostas

> ✏️ Rascunho. Reescreva com as suas palavras e ajuste ao que você observou.

**1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**

Na primeira invocação não existe ambiente pronto (cold start). Antes de rodar o handler, o Lambda precisa criar o ambiente de execução. Essa é a fase de Init: baixar o código, subir o runtime do Python, carregar as extensões e executar o código que está fora do handler (os `import` e a criação da variável global `contador`). Só depois vem a fase Invoke, que roda o `lambda_handler`. Na nuvem, se outra chamada chegar enquanto o ambiente ainda existe, ele é reaproveitado e o Init é pulado, por isso a segunda chamada é mais rápida. Localmente, com `sam local invoke`, cada execução cria um container novo. A diferença grande (19,3 s contra 4,4 s) veio da primeira vez, quando o SAM precisou baixar a imagem Docker do runtime, que ficou em cache para a segunda. O tempo do handler em si foi parecido (~50 ms).

**2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre guardar estado numa variável global?**

Sem `--warm-containers`, o SAM cria um container novo a cada chamada, então o contador sempre voltou para 1 (1, 1, 1). Com `--warm-containers LAZY`, o container é criado na primeira chamada e reaproveitado, e o contador foi 1, 2, 3. As chamadas seguintes também ficaram muito mais rápidas (~30 ms contra ~600 ms). A variável global só sobrevive enquanto o mesmo ambiente estiver vivo. Mas não dá para saber quando ele vai ser descartado, nem se a próxima chamada cai nele: com várias chamadas simultâneas, a AWS cria vários ambientes, cada um com seu próprio contador. Variável global serve como cache (ex.: conexão com banco, configuração carregada), não como estado. Estado de verdade vai para fora da função: DynamoDB, RDS, ElastiCache, S3.

**3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?**

Com Timeout de 3 s, a função dormiu 5 s e foi interrompida em 3 s. O SAM registrou `Function 'HelloWorldFunction' timed out after 3 seconds` e o `curl` recebeu `502 Bad Gateway` com `Internal server error` em vez da guia. Depois de mudar o Timeout para 10 e rodar `sam build`, a mesma chamada demorou cerca de 5 s e retornou 201. O máximo no Lambda é **900 segundos (15 minutos)**. Para trabalho mais longo: quebrar em etapas menores orquestradas pelo AWS Step Functions, processar de forma assíncrona com fila (SQS), ou usar um serviço sem esse limite, como ECS/Fargate ou AWS Batch.

**4. Custo de 1 milhão de execuções com 128 MB e 100 ms (us-east-1)**

- Requisições: 1.000.000 × US$ 0,20 / 1.000.000 = **US$ 0,20**
- Memória em GB: 128 MB / 1024 = 0,125 GB
- GB-s por execução: 0,125 GB × 0,1 s = 0,0125 GB-s
- GB-s total: 0,0125 × 1.000.000 = 12.500 GB-s
- Computação: 12.500 × US$ 0,0000166667 = **US$ 0,2083**
- **Total ≈ US$ 0,41** por milhão de execuções

(Na faixa sempre gratuita, que dá 1 milhão de requisições e 400 mil GB-s por mês, esse volume sairia de graça.)

**5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**

Faz sentido em tarefas curtas, sem estado e acionadas por evento, com demanda irregular: gerar a guia de transporte quando uma requisição é aprovada, enviar notificações (hospital, hemocentro, motorista) quando o status muda, gerar comprovante/PDF da entrega, validar e registrar um pedido recebido por webhook. Não faz sentido no rastreamento em tempo real da bolsa durante o transporte (conexões abertas por muito tempo, WebSocket, fluxo contínuo de GPS), em processamentos longos como otimização de rotas para muitas entregas ou relatórios pesados (podem passar de 15 min), nem em pontos que guardam estado em memória. Também é ruim onde a latência de um cold start atrapalha uma resposta crítica, a não ser que se use concorrência provisionada.

## Evidências

Pasta [`evidencias/`](evidencias/): saídas do `roteiro.sh` e prints de cada passo.

| Arquivo | Conteúdo |
|---|---|
| `00-sam-build.txt` | saída do `sam build` |
| `01-invoke.txt` | duas invocações com evento e tempos |
| `02-curl-sem-warm.txt` | três chamadas HTTP sem reaproveitamento |
| `02-curl-lazy.txt` | três chamadas HTTP com `--warm-containers LAZY` |
| `03-timeout-3s.txt` / `03-timeout-10s.txt` | erro de tempo limite e chamada depois do ajuste |
| `*.png` | prints dos terminais |

Vídeo (até 3 min): ⟨link⟩

> Template final com `Timeout: 10` (depois do ajuste do Passo 5).

## Uso de IA

Conforme PO-CESAR-021.

- **Ferramenta:** Claude (Anthropic).
- **Finalidade:** montar o repositório (template, handler, script `roteiro.sh`, testes), identificar e corrigir o erro de body em base64 no evento gerado pelo SAM, executar os passos no GitHub Codespaces e rascunhar o README e as respostas.
- **Como validei:** ⟨descreva o que você conferiu: ex.: revisei as saídas em `evidencias/`, rodei de novo os comandos ao gravar o vídeo, refiz a conta de custo e comparei as respostas com as minhas⟩
