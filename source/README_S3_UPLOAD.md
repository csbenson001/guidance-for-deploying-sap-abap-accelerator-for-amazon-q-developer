# S3 Upload Enhancement for Margin Data API

## Overview

This enhancement adds S3 upload capability to the `ZSD_SALESORDER_API_MARGIN_BW5` function module, allowing margin data to be exported directly to Amazon S3 in various formats.

## New Features

### Function Module Parameters

New importing parameters added:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `S3_UPLOAD` | CHAR1 | (blank) | Set to 'X' to enable S3 upload |
| `S3_FILE_FORMAT` | CHAR10 | 'PIPE' | Output format: 'JSON', 'PIPE', or 'FIXED' |
| `S3_FILE_NAME` | STRING | (auto) | Custom S3 key/path. If blank, auto-generates |

New exporting parameter:

| Parameter | Type | Description |
|-----------|------|-------------|
| `EV_S3_LOG_ID` | SYSUUID_C32 | Unique ID of the S3 upload log entry |

### Supported File Formats

1. **PIPE** (Default) - Pipe-delimited CSV format
   - Header row with field names
   - Data rows with `|` separator
   - Content-Type: `text/csv`
   - File extension: `.csv`

2. **JSON** - JSON array format
   - Array of objects with lowercase field names
   - Uses SAP `/ui2/cl_json` for serialization
   - Content-Type: `application/json`
   - File extension: `.json`

3. **FIXED** - Fixed-width text format
   - Header row with padded field names
   - Data rows with fixed column widths based on field definitions
   - Content-Type: `text/plain`
   - File extension: `.txt`

## Installation

### 1. Create the Log Table

Create table `ZSD_MGN_S3_LOG` using one of these methods:

**Option A: Using abapGit**
Import `zsd_mgn_s3_log.tabl.xml`

**Option B: Manual creation in SE11**
Use the field definitions in `zsd_mgn_s3_log.ddic.txt`

### 2. Configure TVARVC Parameters

Use transaction `STVARV` to create these parameters:

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `ZSD_MGN_S3_URL` | P | `https://your-api-gateway.execute-api.region.amazonaws.com/prod/` | S3 Gateway URL |
| `ZSD_MGN_S3_API_KEY` | P | `your-api-key` | API Key for X-API-Key header |
| `ZSD_MGN_S3_BUCKET` | P | `your-bucket-name` | Bucket name (for logging) |

### 3. Update Function Module

Replace or merge the code in `zsd_salesorder_api_margin_bw5.abap` with your existing function module.

## Usage Examples

### Example 1: Basic S3 Upload with Pipe-Delimited Format

```json
{
  "APPLICATION": "MAGENTO",
  "S3_UPLOAD": "X",
  "S3_FILE_FORMAT": "PIPE",
  "PARAMETERS": [
    { "NAME": "VAR_NAME_1", "VALUE": "YS_CUST_SLS_MA" },
    { "NAME": "VAR_SIGN_1", "VALUE": "I" },
    { "NAME": "VAR_OPERATOR_1", "VALUE": "EQ" },
    { "NAME": "VAR_VALUE_LOW_EXT_1", "VALUE": "0000261399" }
  ]
}
```

### Example 2: JSON Format with Custom Filename

```json
{
  "APPLICATION": "ANALYTICS",
  "S3_UPLOAD": "X",
  "S3_FILE_FORMAT": "JSON",
  "S3_FILE_NAME": "exports/2024/margin_data_analyst_261399.json",
  "MARGIN_ANALYST": "0000261399",
  "PARAMETERS": [
    { "NAME": "VAR_NAME_1", "VALUE": "YS_CUST_SLS_MA" },
    { "NAME": "VAR_SIGN_1", "VALUE": "I" },
    { "NAME": "VAR_OPERATOR_1", "VALUE": "EQ" },
    { "NAME": "VAR_VALUE_LOW_EXT_1", "VALUE": "0000261399" }
  ]
}
```

### Example 3: Fixed-Width Format

```json
{
  "APPLICATION": "LEGACY_SYSTEM",
  "S3_UPLOAD": "X",
  "S3_FILE_FORMAT": "FIXED",
  "PARAMETERS": [
    { "NAME": "VAR_NAME_1", "VALUE": "YSLAST_ADJ_MTH" },
    { "NAME": "VAR_VALUE_EXT_1", "VALUE": "012024" }
  ]
}
```

## Auto-Generated File Names

When `S3_FILE_NAME` is not provided, the system generates:

```
margin_data/{SYSID}/{MANDT}/margin_export_{YYYYMMDDHHMMSS}.{ext}
```

Example: `margin_data/PRD/100/margin_export_20240115143022.csv`

## S3 Upload Log

All uploads are logged in table `ZSD_MGN_S3_LOG` with:

- Upload timestamp and user
- S3 bucket and key
- File format and size
- Record count
- HTTP status code
- Success/failure status and message
- Duration in milliseconds
- Correlation ID for tracing

### Viewing Logs

```sql
SELECT * FROM zsd_mgn_s3_log
  WHERE upload_date = '20240115'
  ORDER BY upload_time DESCENDING.
```

## AWS Infrastructure Requirements

### API Gateway Setup

The S3 upload uses HTTP PUT to an API Gateway endpoint. Your AWS setup should include:

1. **API Gateway** with:
   - PUT method enabled
   - API Key authentication (optional)
   - Integration with S3 PutObject

2. **IAM Role** with S3 write permissions:
   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:PutObject"],
     "Resource": "arn:aws:s3:::your-bucket/*"
   }
   ```

3. **S3 Bucket** configured for the data

### Sample API Gateway Integration

```yaml
paths:
  /{proxy+}:
    put:
      x-amazon-apigateway-integration:
        type: aws
        httpMethod: PUT
        uri: arn:aws:apigateway:region:s3:path/{bucket}/{key}
        credentials: arn:aws:iam::account:role/api-gateway-s3-role
        requestParameters:
          integration.request.path.bucket: 'your-bucket'
          integration.request.path.key: 'method.request.path.proxy'
```

## Error Handling

The function module handles errors gracefully:

- S3 upload failures are logged but don't fail the overall function
- The main data retrieval and database operations complete normally
- Return message includes S3 status information
- All errors are recorded in the log table

## Performance Considerations

- JSON serialization uses SAP's optimized `/ui2/cl_json` class
- Large datasets may take time to serialize and upload
- Upload duration is tracked in the log table
- Consider batch sizes for very large exports

## Troubleshooting

### Common Issues

1. **HTTP 403 Forbidden**
   - Check API Key configuration in TVARVC
   - Verify API Gateway authentication settings

2. **HTTP 400 Bad Request**
   - Check URL format in TVARVC
   - Verify S3 key path is valid

3. **Connection Timeout**
   - Check SAP ICM timeout settings
   - Verify network connectivity to AWS

4. **No data uploaded**
   - Verify `S3_UPLOAD = 'X'` is passed
   - Check that data was retrieved (records exist)

### Debug Mode

Enable HTTP trace in transaction `SMICM` > `Goto` > `Trace File` > `Display` to see HTTP request/response details.
