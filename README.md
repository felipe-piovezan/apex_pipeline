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
    "object_filters": {
      "include_objects": ["TABLE:USER_*", "VIEW:VW_*"],
      "exclude_objects": ["TABLE:TEMP_*", "SEQUENCE:SEQ_TEMP_*"]
    }
  }
}
```

### Filtros de Objetos de Banco

Os filtros `object_filters` são opcionais e permitem controlar quais objetos do banco são exportados pelo Liquibase:

- **`include_objects`**: Array de padrões para incluir objetos específicos (se vazio, inclui todos)
- **`exclude_objects`**: Array de padrões para excluir objetos específicos

**Formato dos padrões:**
- `TABLE:PATTERN` - Filtrar tabelas
- `VIEW:PATTERN` - Filtrar views  
- `SEQUENCE:PATTERN` - Filtrar sequences
- `FUNCTION:PATTERN` - Filtrar functions
- `PROCEDURE:PATTERN` - Filtrar procedures

**Exemplos:**
- `"TABLE:USER_*"` - Todas as tabelas que começam com "USER_"
- `"VIEW:VW_*"` - Todas as views que começam com "VW_"  
- `"SEQUENCE:SEQ_TEMP_*"` - Todas as sequences que começam com "SEQ_TEMP_"

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
