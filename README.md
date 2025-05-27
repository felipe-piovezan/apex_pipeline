# apex_pipeline

## Configuração

Edite o arquivo `config.json` para especificar quais aplicações APEX devem ser exportadas/deployadas e filtros de objetos de banco:

```json
{
  "apex": {
    "applications": [104, 110],
    "export_options": {
      "skipExportDate": true,
      "expOriginalIds": true,
      "expSupportingObjects": "Y",
      "expType": "APPLICATION_SOURCE"
    }
  },
  "database": {
    "ddl_options": {
      "storage": "off",
      "partitioning": "off",
      "segment_attributes": "off",
      "tablespace": "off",
      "emit_schema": "off"
    },
    "object_filter": "LIKE 'PKG_%' AND NOT LIKE 'VW_%'"
  }
}
```

### Filtro de Objetos de Banco

O parâmetro `object_filter` é opcional e permite controlar quais objetos do banco são exportados pelo Liquibase. O valor é passado diretamente para o parâmetro `-filter` do SQLcl.

**Sintaxe**: O filtro deve ser uma expressão SQL válida que será anexada à consulta de metadados do banco.

**Exemplos:**
```json
{
  "database": {
    "object_filter": "LIKE 'PKG_%' AND NOT LIKE 'VW_%'"
  }
}
```

```json
{
  "database": {
    "object_filter": "IN('FACEID_BENEFICIARIO_PARAM', 'DATABASECHANGELOG_ACTIONS')"
  }
}
```

```json
{
  "database": {
    "object_filter": "NOT LIKE 'TEMP_%'"
  }
}
```

**Operadores suportados:**
- `LIKE 'PATTERN'` - Coincidência com padrão (% = qualquer string, _ = qualquer caractere)
- `IN('OBJ1', 'OBJ2')` - Lista específica de objetos
- `NOT LIKE 'PATTERN'` - Exclusão por padrão
- `= 'EXACT_NAME'` - Nome exato
- Combinações com `AND`, `OR`

## Utilização

### Export
```bash
./apexexport.sh <SCHEMA_NAME>/"<SCHEMA_PASSWORD>"@<DB_HOST>:<DB_PORT>/<DB_SERVICE_NAME> [WORK_DIR] [CONFIG_FILE]
```

### Deploy
```bash
./apexdeploy.sh <SCHEMA_NAME>/"<SCHEMA_PASSWORD>"@<DB_HOST>:<DB_PORT>/<DB_SERVICE_NAME> [WORK_DIR] [CONFIG_FILE]
```

### Via curl (remoto)
```bash
curl -fsSL https://raw.githubusercontent.com/felipe-piovezan/apex_pipeline/refs/heads/main/apexexport.sh | bash -s -- <SCHEMA_NAME>/"<SCHEMA_PASSWORD>"@<DB_HOST>:<DB_PORT>/<DB_SERVICE_NAME>
```

**Parâmetros:**
- `SCHEMA_NAME/PASSWORD@HOST:PORT/SERVICE` - String de conexão Oracle (obrigatório)
- `WORK_DIR` - Diretório de trabalho (padrão: diretório atual)
- `CONFIG_FILE` - Arquivo de configuração (padrão: config.json no mesmo diretório do script)