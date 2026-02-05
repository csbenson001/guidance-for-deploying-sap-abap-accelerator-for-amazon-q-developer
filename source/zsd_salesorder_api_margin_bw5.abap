FUNCTION zsd_salesorder_api_margin_bw5.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(APPLICATION) TYPE  STRING OPTIONAL
*"     VALUE(MARGIN_ANALYST) TYPE  KUNNR OPTIONAL
*"     VALUE(QUERY_DEFAULTS) TYPE  STRING DEFAULT 'MARGIN'
*"     VALUE(PARAMETERS) TYPE  RRXW3TQUERY OPTIONAL
*"     VALUE(VIEW_ID) TYPE  RSZVIEWID OPTIONAL
*"     VALUE(INFOPROVIDER) TYPE  RSINFOPROV DEFAULT 'YMARGINM1'
*"     VALUE(QUERY) TYPE  RSZCOMPID DEFAULT 'YYMARGINM1_Q001'
*"     VALUE(CLEAR_TABLE) TYPE  CHAR1 DEFAULT 'X'
*"     VALUE(APPEND_TABLE) TYPE  CHAR1 DEFAULT 'X'
*"     VALUE(OUTPUT_DATA) TYPE  CHAR1 DEFAULT 'X'
*"     VALUE(OUTPUT_TYPE) TYPE  CHAR10 DEFAULT 'FULL'
*"     VALUE(APPLY_WRKITEM_DATA) TYPE  CHAR1 DEFAULT 'X'
*"     VALUE(S3_UPLOAD) TYPE  CHAR1 OPTIONAL
*"     VALUE(S3_FILE_FORMAT) TYPE  CHAR10 DEFAULT 'PIPE'
*"     VALUE(S3_FILE_NAME) TYPE  STRING OPTIONAL
*"  EXPORTING
*"     VALUE(RETURN) TYPE  BAPIRET2
*"     VALUE(EV_SUCCESS) TYPE  CHAR1
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RECORDS_INSERTED) TYPE  INT4
*"     VALUE(TBL_MARGIN_DATA_SMALL) TYPE  ZSD_MGN_BASE_RPT_SMALL_TT
*"     VALUE(TBL_MARGIN_DATA) TYPE  ZSD_MGN_BASE_RPT_TT
*"     VALUE(EV_S3_LOG_ID) TYPE  SYSUUID_C32
*"----------------------------------------------------------------------
* call it like this
  "{
  "  "APPLICATION": "MAGENTO",
  "  "S3_UPLOAD": "X",
  "  "S3_FILE_FORMAT": "PIPE",
  "  "PARAMETERS": [
  "    { "NAME": "VAR_NAME_1", "VALUE": "YS_CUST_SLS_MA" },
  "    { "NAME": "VAR_SIGN_1", "VALUE": "I" },
  "    { "NAME": "VAR_OPERATOR_1", "VALUE": "EQ" },
  "    { "NAME": "VAR_VALUE_LOW_EXT_1", "VALUE": "0000261399" },
  "    { "NAME": "VAR_NAME_2", "VALUE": "YSLAST_ADJ_MTH" },
  "    { "NAME": "VAR_VALUE_EXT_2", "VALUE": "012026" }
  "    ]
  "}

  DATA i_infoprovider TYPE rsinfoprov VALUE 'YMARGINM1'.
  DATA i_query        TYPE rszcompid VALUE 'YYMARGINM1_Q001'.
  DATA i_view_id      TYPE rszviewid.
  DATA i_t_parameter  TYPE rrxw3tquery.
  DATA e_axis_info    TYPE rrws_thx_axis_info.
  DATA e_cell_data    TYPE rrws_t_cell.
  DATA e_axis_data    TYPE rrws_thx_axis_data.
  DATA e_txt_symbols  TYPE rrws_t_text_symbols.
  DATA: lv_destination TYPE rfcdes.
  DATA: lv_bw_destination TYPE rvari_val_255.
  CONSTANTS: c_margin_bw TYPE rvari_vnam VALUE 'ZSD_SALESORDER_API_MARGIN_BW'.
  CONSTANTS: c_margin_qry TYPE rvari_vnam VALUE 'ZSD_SALESORDER_API_MARGIN_BW_I'.

  " S3 Upload configuration constants
  CONSTANTS: c_s3_url_tvarvc TYPE rvari_vnam VALUE 'ZSD_MGN_S3_URL'.
  CONSTANTS: c_s3_api_tvarvc TYPE rvari_vnam VALUE 'ZSD_MGN_S3_API_KEY'.
  CONSTANTS: c_s3_bucket_tvarvc TYPE rvari_vnam VALUE 'ZSD_MGN_S3_BUCKET'.

  DATA:
    e_t_cell_data          TYPE TABLE OF bapi6111cd,
    e_t_axis_info          TYPE TABLE OF  rrx_axis_info,
    e_t_axis_chars         TYPE TABLE OF rrx_axis_chars,
    e_t_axis_attrs         TYPE TABLE OF rrx_axis_attrs,
    e_t_axis_data_columns  TYPE TABLE OF  rrx_x_axis_data,
    e_t_axis_data_rows     TYPE TABLE OF rrx_x_axis_data,
    e_t_axis_data_slicer   TYPE TABLE OF rrx_x_axis_data,
    e_t_attr_data_rows     TYPE TABLE OF rrx_x_attr_data,
    e_t_attr_data_columns  TYPE TABLE OF  rrx_x_attr_data,
    e_t_text_symbols       TYPE TABLE OF rrws_s_text_symbols,
    e_t_messages           TYPE TABLE OF smesg.

  " Check if defaults should be auto-enabled via TVARVC
  SELECT SINGLE low INTO @lv_bw_destination
    FROM tvarvc
    WHERE name = @c_margin_bw
      AND type = 'P'.
  IF lv_bw_destination IS NOT INITIAL.
    MOVE lv_bw_destination TO lv_destination.
  ELSE.
    return-message = 'No destination defined'.
    return-type = 'E'.
    EXIT.
  ENDIF.

  IF infoprovider IS NOT INITIAL.
    MOVE infoprovider TO i_infoprovider.
  ENDIF.
  IF query IS NOT INITIAL.
    MOVE query TO i_query.
  ENDIF.

* verify that this is active and eligible for the api.
  DATA: ls_restapi_bw TYPE zsap_restapi_bw.
  CLEAR ls_restapi_bw.
  SELECT SINGLE * INTO ls_restapi_bw FROM zsap_restapi_bw
    WHERE infoprovider = i_infoprovider
      AND query = i_query
      AND config_value = 'ACTIVE'.
  IF sy-subrc <> 0.
    return-message = 'Query not authorized in zsap_restapi_bw.  Exiting'.
    return-type = 'E'.
    EXIT.
  ENDIF.

  IF parameters IS INITIAL.
    return-message = 'You must supply filter parameters'.
    return-type = 'E'.
    EXIT.
  ENDIF.

  READ TABLE parameters WITH KEY name = space TRANSPORTING NO FIELDS.
  IF sy-subrc = 0.
    return-message = 'At least one parameter name is empty'.
    return-type = 'E'.
    EXIT.
  ENDIF.

  IF view_id IS NOT INITIAL.
    MOVE view_id TO i_view_id.
  ENDIF.
  i_t_parameter  = parameters.

  CALL FUNCTION 'RS_VC_GET_QUERY_VIEW_DATA_FLAT'
    DESTINATION lv_destination
    EXPORTING
      i_infoprovider          = i_infoprovider
      i_query                 = i_query
      i_view_id               = i_view_id
      i_max_rows              = -1
    TABLES
      i_t_parameter           = i_t_parameter
      e_t_cell_data           = e_t_cell_data
      e_t_axis_info           = e_t_axis_info
      e_t_axis_chars          = e_t_axis_chars
      e_t_axis_attrs          = e_t_axis_attrs
      e_t_axis_data_columns   = e_t_axis_data_columns
      e_t_axis_data_rows      = e_t_axis_data_rows
      e_t_axis_data_slicer    = e_t_axis_data_slicer
      e_t_attr_data_rows      = e_t_attr_data_rows
      e_t_attr_data_columns   = e_t_attr_data_columns
      e_t_text_symbols        = e_t_text_symbols
      e_t_messages            = e_t_messages
    EXCEPTIONS
      no_applicable_data      = 1
      invalid_variable_values = 2
      no_authority            = 3
      abort                   = 4
      invalid_input           = 5
      invalid_view            = 6
      OTHERS                  = 7.
  IF sy-subrc <> 0.
    return-type = 'E'.
    return-message = 'Error retrieving data ' && sy-msgno && '| subrc ' && sy-subrc.
    EXIT.
  ENDIF.

  DATA: ls_record      TYPE zsd_mgn_base_rpt,
        lt_tuple_index TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line,
        lv_row_idx     TYPE i,
        lv_num_cols    TYPE i.

  TYPES: BEGIN OF ty_keyfig_map,
           caption TYPE string,
           field   TYPE string,
         END OF ty_keyfig_map.

  FIELD-SYMBOLS: <fs_row>   TYPE rrx_x_axis_data,
                 <fs_col>   TYPE rrx_x_axis_data,
                 <fs_cell>  TYPE rrws_s_cell,
                 <fs_field> TYPE any.

  DATA: BEGIN OF mt_dimension_map OCCURS 100,
          chanm TYPE string,
          field TYPE string,
        END OF mt_dimension_map.
  DATA ls_dimension_map LIKE LINE OF mt_dimension_map.

  CLEAR mt_dimension_map.
  " Core Keys
  APPEND VALUE #( chanm = 'YVBELV' field = 'VBELV' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM' field = 'POSNV' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUSTOMER' field = 'KUNAG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0SHIP_TO' field = 'KUNWE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL' field = 'MATNR' ) TO mt_dimension_map.
  " Organization
  APPEND VALUE #( chanm = '0SALESORG' field = 'SALESORG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DISTR_CHAN' field = 'DISTR_CHAN' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DIVISION' field = 'SPART' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0COMP_CODE' field = 'COMP_CODE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PLANT' field = 'PLANT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PLANT__0PLANTCAT' field = 'PLANT_CAT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PLANT__YHUB_TER' field = 'PLANT_HUB' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PLANT__YPLANTACT' field = 'PLANTACCT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PLANT__YCTLPLNT' field = 'CTL_PLANT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0COMP_CODE__YGLREGION' field = 'GLOBAL_REG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0COMP_CODE__YSUBREGN' field = 'SUB_REGION' ) TO mt_dimension_map.
  " Documents
  APPEND VALUE #( chanm = '0BILL_NUM' field = 'BILL_NUM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILL_ITEM' field = 'BILL_ITEM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILL_DATE' field = 'BILL_DATE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILL_TYPE' field = 'BILL_TYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DOC_NUMBER' field = 'DOC_NUMBER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DOC_TYPE' field = 'DOC_TYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DOC_ITEM' field = 'DOC_ITEM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CO_DOC_NO' field = 'CO_DOC_NO' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0SORD_ITEM' field = 'SORD_ITEM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSORDNUM' field = 'YSORDNUM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSORDITM' field = 'YSORDITM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0REFER_DOC' field = 'REFER_DOC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0REFER_ITM' field = 'REFER_ITM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPONUMBR' field = 'PONUMBR' ) TO mt_dimension_map.
  " Dates
  APPEND VALUE #( chanm = '0PSTNG_DATE' field = 'PSTNG_DATE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CREATEDON' field = 'CREATEDON' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YORDCRTON' field = 'ORDCRTON' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YRQDELDAT' field = 'RQDELDAT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSLDELDAT' field = 'SLDELDAT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0FISCYEAR' field = 'FISCYEAR' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0FISCPER' field = 'FISCPER' ) TO mt_dimension_map.
  " Material
  APPEND VALUE #( chanm = '0BASE_UOM' field = 'BASE_UOM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YBASECODE' field = 'BASECODE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YCONTCODE' field = 'CONTCODE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YCONTABBR' field = 'CONTABBR' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__0MATL_TYPE' field = 'MATL_TYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YMATSEG' field = 'MATSEG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YGRADENUM' field = 'GRADENUM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YFOODFL' field = 'FOODFL' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YEHS_CAS' field = 'EHS_CAS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__YKZWSM' field = 'KZWSM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__0DIVISION' field = 'MAT_DIV' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATERIAL__0ME_AUTHGRP' field = 'ME_AUTHGRP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSKUUOM' field = 'SKU_UOM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBATCHMAT' field = 'BATCHMAT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YMODMATD' field = 'MODMATD' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCMATNR' field = 'CMATNR' ) TO mt_dimension_map.
  " Material Groups
  APPEND VALUE #( chanm = '0MAT_SALES__0MATL_GRP_2' field = 'MG2' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MATL_GRP_3' field = 'MG3' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MAT_SALES__0MATL_GRP_4' field = 'MG4' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MAT_SALES__YHORZ' field = 'HORZ' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MAT_SALES__YHORZRLP' field = 'HORZRLP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MAT_SALES__YVMSTA' field = 'VMSTA' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0MAT_SALES' field = 'MAT_SALES' ) TO mt_dimension_map.
  " Customer Groups
  APPEND VALUE #( chanm = '0CUST_GROUP' field = 'CUST_GROUP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUST_GRP2' field = 'CUST_GRP2' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUST_GRP3' field = 'CUST_GRP3' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUST_GRP4' field = 'CUST_GRP4' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUST_GRP5' field = 'CUST_GRP5' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUSTOMER__0CUST_CLASS' field = 'CUST_CLASS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUSTOMER__0INDUSTRY' field = 'INDUSTRY' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0CUSTOMER__YACQUISRC' field = 'ACQU_SRC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSDCTCGP1' field = 'SDCTCGP1' ) TO mt_dimension_map.
  " Customer Sales (YCUST_SLS)
  APPEND VALUE #( chanm = 'YCUST_SLS' field = 'CUST_SLS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__0CUST_CLA' field = 'ABC_CLASS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSR' field = 'LCSR' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLSELLER' field = 'LSELLER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSELLER' field = 'HSELLER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSELM' field = 'HSELM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSELMM' field = 'HSELMM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSLSGRP' field = 'HSLSGRP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSLSOFF' field = 'HSLSOFF' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YHSLSDIST' field = 'HSLSDIST' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YDIVNODE' field = 'DIVNODE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YMRGNANLT' field = 'MRGNANLT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YDZ_CSR' field = 'DZ_CSR' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSTGRP1' field = 'LCSTGRP1' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSTGRP2' field = 'LCSTGRP2' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSTGRP3' field = 'LCSTGRP3' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSTGRP4' field = 'LCSTGRP4' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLCSTGRP5' field = 'LCSTGRP5' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YINFSLR1' field = 'INFSLR1' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YINFSLR2' field = 'INFSLR2' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YINFSLR3' field = 'INFSLR3' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YLDOG' field = 'LDOG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YZTER' field = 'ZTER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YZTER_YI1' field = 'ZTER_YI1' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YZTER_YI2' field = 'ZTER_YI2' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__YZTER_YI3' field = 'ZTER_YI3' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YCUST_SLS__0PMNTTRMS' field = 'PMNTTRMS_S' ) TO mt_dimension_map.
  " LOB
  APPEND VALUE #( chanm = 'YLOB' field = 'LOB' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YLOBRU' field = 'LOBRU' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YLOB__YLOBDIV' field = 'LOBDIV' ) TO mt_dimension_map.
  " Vendor
  APPEND VALUE #( chanm = '0VENDOR' field = 'VENDOR' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YGSVEND' field = 'GSVEND' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'Y3P_PONUM' field = 'Y3P_PONUM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'Y3P_POITM' field = 'Y3P_POITM' ) TO mt_dimension_map.
  " Shipping
  APPEND VALUE #( chanm = '0ITEM_CATEG' field = 'ITEM_CATEG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0ITEM_CATEG__YHOW_SHIP' field = 'HOW_SHIP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0SHIP_COND' field = 'SHIP_COND' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0INCOTERMS' field = 'INCOTERMS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILLTOPRTY' field = 'BILLTOPRTY' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILL_BLOCK' field = 'BILL_BLOCK' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0BILBLK_ITM' field = 'BILBLK_ITM' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_CARTP' field = 'CARRIER_TP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_FOID' field = 'TM_FOID' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0TM_SFIRID' field = 'TM_SFIRID' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0TM_PURORID' field = 'TM_PURORID' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_FOID__0TM_EXEC' field = 'FO_EXEC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_FOID__0TM_EXESCAC' field = 'FO_EXESCAC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_FOID__0TM_TSP' field = 'FO_TSP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YTM_FOID__0TM_TSPSCAC' field = 'FO_TSPSCAC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0COUNTRY' field = 'COUNTRY' ) TO mt_dimension_map.
  " Pricing
  APPEND VALUE #( chanm = 'YCONDTYP' field = 'CONDTYP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPRCTYPE' field = 'PRCTYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0KNART' field = 'KNART' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0PMNTTRMS' field = 'PMNTTRMS' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0RECTYPE' field = 'RECTYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YREFPROC' field = 'REFPROC' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YREC_WAER' field = 'REC_WAER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0DOC_CURRCY' field = 'DOC_CURRCY' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOTYPE' field = 'POTYPE' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0ACCNT_ASGN' field = 'ACCNT_ASGN' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = '0COSTELMNT' field = 'COSTELMNT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YSKOST' field = 'SKOST' ) TO mt_dimension_map.
  " Hierarchy
  APPEND VALUE #( chanm = 'YPHSEG' field = 'PHSEG' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPFT_HIER' field = 'PFT_HIER' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBWZPT' field = 'BWZPT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'UU_SRCSYS' field = 'SRCSYS' ) TO mt_dimension_map.
  " Order Info
  APPEND VALUE #( chanm = '0ORD_REASON' field = 'ORD_REASON' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YORDCRTBY' field = 'ORDCRTBY' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBNAME' field = 'BNAME' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YESBILFLG' field = 'ESBILFLG' ) TO mt_dimension_map.
  " Batch
  APPEND VALUE #( chanm = 'YBATCHMAT__YARRDAT' field = 'ARRDAT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBATCHMAT__YPRGMAIN' field = 'PRGMAIN' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBATCHMAT__YPRGSUB' field = 'PRGSUB' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBATCHMAT__YWASTPROF' field = 'WASTPROF' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YBATCHMAT__YWASTEVEN' field = 'WASTEVEN' ) TO mt_dimension_map.
  " MA Fields
  APPEND VALUE #( chanm = 'YPOSNVM__YMAREASON' field = 'MA_REASON' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM__YMAOWNSHP' field = 'MA_OWNSHP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM__YMAFLWUP' field = 'MA_FLWUP' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM__YMA_CLSST' field = 'MA_CLSST' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM__YLSTADJDT' field = 'LSTADJDT' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YPOSNVM__YCMCMBDT' field = 'CMCMBDT' ) TO mt_dimension_map.
  " Other
  APPEND VALUE #( chanm = '0MATL_GRP_2__YPSANLYST' field = 'PSANLYST' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YWASTEDTL' field = 'WASTEDTL' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YAB_LFTYV' field = 'AB_LFTYV' ) TO mt_dimension_map.
  APPEND VALUE #( chanm = 'YAB_LFTYN' field = 'AB_LFTYN' ) TO mt_dimension_map.

  " ================================================================
  " ATTRIBUTE MAPPINGS (attrinm -> field) - All 7
  " ================================================================
  DATA: BEGIN OF mt_attr_map OCCURS 100,
          attrinm TYPE string,
          field   TYPE string,
        END OF mt_attr_map.
  DATA ls_attr_map LIKE LINE OF mt_attr_map.

  CLEAR mt_attr_map.
  APPEND VALUE #( attrinm = 'YMAHRDSFT' field = 'HARD_SOFT' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YCSPCHGF' field = 'CSP_CHG_F' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YMAWITXT1' field = 'COMMENT1' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YMAWITXT2' field = 'COMMENT2' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YMAWITXT3' field = 'COMMENT3' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YMAWITXT4' field = 'COMMENT4' ) TO mt_attr_map.
  APPEND VALUE #( attrinm = 'YRCVRDAMT' field = 'RECOVERED_AMT' ) TO mt_attr_map.

  DATA: BEGIN OF mt_keyfig_map OCCURS 100,
          field   TYPE string,
          caption TYPE string,
        END OF mt_keyfig_map.

  " ================================================================
  " KEY FIGURE MAPPINGS (caption -> field) - All 78 KFs
  " ================================================================
  CLEAR mt_keyfig_map.
  APPEND VALUE #( caption = 'LB' field = 'KF_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'KG' field = 'KF_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Sales Rebate' field = 'KF_SALES_REB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Cash Discounts' field = 'KF_CASH_DISC' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Freight Charged to Cust - YVVFRE USD' field = 'KF_FRT_CHRG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Total Sales Deductions COPA' field = 'KF_TOT_DEDUC' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Sales Surcharge' field = 'KF_SALES_SUR' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Logistics Charge' field = 'KF_LOG_CHRG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Tariff Surcharge' field = 'KF_TAR_SUR' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Revenue' field = 'KF_REVENUE' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Revenue Customer' field = 'KF_REV_CUST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Price Support External Vendor' field = 'KF_PS_EXT_VND' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Price Support External Vendor / LB' field = 'KF_PS_EXT_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Price Support External Vendor / KG' field = 'KF_PS_EXT_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS' field = 'KF_COGS' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Warehouse Charges' field = 'KF_WH_CHRG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'OB Freight Std Rate Charges' field = 'KF_OB_FRT_STD' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COPA Total W&D Charge' field = 'KF_TOT_WD_CHG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Net Revenue' field = 'KF_NET_REV' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Net Rev / LB' field = 'KF_NET_REV_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Net Rev / KG' field = 'KF_NET_REV_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM' field = 'KF_GM' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM %' field = 'KF_GM_PCT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM / LB' field = 'KF_GM_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM / KG' field = 'KF_GM_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM' field = 'KF_CM' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM / LB' field = 'KF_CM_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM / KG' field = 'KF_CM_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Moving PUP' field = 'KF_CM_MOV_PUP' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Moving PUP %' field = 'KF_CM_MOV_PUP_PCT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Moving PUP / LB' field = 'KF_CM_MOV_PUP_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Moving PUP / KG' field = 'KF_CM_MOV_PUP_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Moving PUP Cost' field = 'KF_MOV_PUP_CST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Moving PUP Cost / LB' field = 'KF_MOV_PUP_CST_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Moving PUP Cost / KG' field = 'KF_MOV_PUP_CST_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZCMB Cond Value' field = 'KF_ZCMB_VAL' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZCMQ %' field = 'KF_ZCMQ_PCT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZCMB Per LB' field = 'KF_ZCMB_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZCMB Per KG' field = 'KF_ZCMB_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZPUP MA PUP Cost' field = 'KF_ZPUP_MA_CST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'ZPUP MA PUP Cost / LB' field = 'KF_ZPUP_MA_CST_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO PO 3P Cost' field = 'KF_SO_PO_3P' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO PO 3P Cost / LB' field = 'KF_SO_PO_3P_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO PO 3P Cost / KG' field = 'KF_SO_PO_3P_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO CM PO 3P Cost' field = 'KF_SO_CM_PO_3P' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO CM PO 3P Cost %' field = 'KF_SO_CM_PO_3P_PCT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO CM PO Cost / LB' field = 'KF_SO_CM_PO_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO CM PO Cost / KG' field = 'KF_SO_CM_PO_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO PUP Cost / LB - SO Cost / LB' field = 'KF_PUP_COST_D_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO PUP Cost / KG - SO Cost / KG' field = 'KF_PUP_COST_D_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Moving PUP - SO ZCMB Initial' field = 'KF_CM_PUP_ZCMB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO Moving PUP Cost / LB - SO ZCMB / LB Initial' field = 'KF_PUP_ZCMB_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO Moving PUP Cost / KG - SO ZCMB / KG Initial' field = 'KF_PUP_ZCMB_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Satellite Adder Cond Z485' field = 'KF_SAT_ADD_Z485' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Satellite Commission Condition Z486' field = 'KF_SAT_COM_Z486' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Moving PUP' field = 'KF_COGS_MOV_PUP' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Moving PUP / LB' field = 'KF_COGS_MOV_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Moving PUP / KG' field = 'KF_COGS_MOV_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO GM PUP' field = 'KF_SO_GM_PUP' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO COGS PO Cost' field = 'KF_SO_COGS_PO' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO COGS PO Cost / LB' field = 'KF_SO_COGS_PO_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO COGS PO Cost / KG' field = 'KF_SO_COGS_PO_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'SO GM PO 3P Cost' field = 'KF_SO_GM_PO_3P' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Est Calc' field = 'KF_COGS_EST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Est Calc / LB' field = 'KF_COGS_EST_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'COGS Est Calc / KG' field = 'KF_COGS_EST_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM Est Calc' field = 'KF_GM_EST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM Est Calc / LB' field = 'KF_GM_EST_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'GM Est Calc / KG' field = 'KF_GM_EST_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Est Calc' field = 'KF_CM_EST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Est Calc / LB' field = 'KF_CM_EST_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Est Calc / KG' field = 'KF_CM_EST_KG' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM % Est Calc' field = 'KF_CM_PCT_EST' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Baseline Recovery Amt' field = 'KF_BASE_RECV_AMT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Est Baseline' field = 'KF_CM_EST_BASE' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'CM Baseline Date' field = 'KF_CM_BASE_DT' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Selling Price / LB' field = 'KF_SELL_PRC_LB' ) TO mt_keyfig_map.
  APPEND VALUE #( caption = 'Billing Price per LB' field = 'KF_BILL_PRC_LB' ) TO mt_keyfig_map.

  " Build unique tuple list
  DATA lv_last_tuple TYPE string.
  LOOP AT e_t_axis_data_rows ASSIGNING <fs_row>.
    IF <fs_row>-tuple_ordinal <> lv_last_tuple.
      lv_last_tuple = <fs_row>-tuple_ordinal.
      INSERT lv_row_idx INTO TABLE lt_tuple_index.
      lv_row_idx = lv_row_idx + 1.
    ENDIF.
  ENDLOOP.

  " Process each tuple (row)
  lv_row_idx = 0.
  lv_last_tuple = '999999'. "dummy starter
  DATA: et_flat_records TYPE TABLE OF zsd_mgn_base_rpt.
  CLEAR et_flat_records.

  LOOP AT e_t_axis_data_rows ASSIGNING <fs_row>.
    " New tuple = new record
    IF <fs_row>-tuple_ordinal <> lv_last_tuple.
      IF lv_last_tuple IS NOT INITIAL AND ls_record-vbelv IS NOT INITIAL.
        " Save previous record
        ls_record-erdat = sy-datum.
        ls_record-ertim = sy-uzeit.
        APPEND ls_record TO et_flat_records.
      ENDIF.
      CLEAR ls_record.
      lv_last_tuple = <fs_row>-tuple_ordinal.
      lv_row_idx = lv_row_idx + 1.
    ENDIF.

    " Map dimension value to field
    READ TABLE mt_dimension_map INTO DATA(ls_dim) WITH KEY chanm = <fs_row>-chanm.
    IF sy-subrc = 0.
      ASSIGN COMPONENT ls_dim-field OF STRUCTURE ls_record TO <fs_field>.
      IF sy-subrc = 0.
        " Prefer chavl_ext over chavl
        IF <fs_row>-chavl_ext IS NOT INITIAL AND <fs_row>-chavl_ext <> '#'.
          PERFORM clean_sap_value CHANGING <fs_row>-chavl_ext.
          <fs_field> = <fs_row>-chavl_ext.
        ELSE.
          PERFORM clean_sap_value CHANGING <fs_row>-chavl.
          <fs_field> = <fs_row>-chavl.
        ENDIF.
      ENDIF.
    ENDIF.

    " Also capture caption for description fields
    IF <fs_row>-chanm = '0SHIP_TO'.
      PERFORM clean_sap_value CHANGING <fs_row>-caption.
      ls_record-kunwe_name = <fs_row>-caption.
    ELSEIF <fs_row>-chanm = '0MATERIAL'.
      PERFORM clean_sap_value CHANGING <fs_row>-caption.
      ls_record-maktx = <fs_row>-caption.
    ELSEIF <fs_row>-chanm = 'YPOSNVM__YMAREASON'.
      PERFORM clean_sap_value CHANGING <fs_row>-caption.
      ls_record-ma_reason_t = <fs_row>-caption.
    ENDIF.
    ls_record-tuple = <fs_row>-tuple_ordinal.
  ENDLOOP.

  " Save last record
  IF ls_record-vbelv IS NOT INITIAL.
    ls_record-erdat = sy-datum.
    ls_record-ertim = sy-uzeit.
    APPEND ls_record TO et_flat_records.
  ENDIF.

  " Now process attributes
  FIELD-SYMBOLS: <fs_attr> TYPE rrx_x_attr_data.
  LOOP AT e_t_attr_data_rows ASSIGNING <fs_attr>.
    " Find matching record by tuple
    READ TABLE et_flat_records ASSIGNING FIELD-SYMBOL(<fs_rec>)
      WITH KEY tuple = <fs_attr>-tuple_ordinal.
    IF sy-subrc = 0 AND <fs_rec> IS ASSIGNED.
      READ TABLE mt_attr_map INTO DATA(ls_attr) WITH KEY attrinm = <fs_attr>-attrinm.
      IF sy-subrc = 0.
        " Apply to matching record
        ASSIGN COMPONENT ls_attr-field OF STRUCTURE ls_record TO <fs_field>.
        IF sy-subrc = 0.
          TRY.
              IF <fs_attr>-attrivl IS NOT INITIAL AND <fs_attr>-attrivl <> '#'.
                PERFORM clean_sap_value CHANGING <fs_attr>-attrivl.
                <fs_field> = <fs_attr>-attrivl.
              ELSE.
                PERFORM clean_sap_value CHANGING <fs_attr>-attrivl.
                <fs_field> = <fs_attr>-attrivl.
              ENDIF.
            CATCH cx_root.
              CLEAR <fs_field>.
          ENDTRY.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Process cell data (key figures)
  DATA lv_ordinal TYPE i.
  DESCRIBE TABLE e_t_axis_data_columns LINES lv_num_cols.
  LOOP AT e_t_cell_data ASSIGNING <fs_cell>.
    lv_ordinal = <fs_cell>-cell_ordinal.
    DATA(lv_rec_idx) = lv_ordinal DIV lv_num_cols + 1.
    DATA(lv_col_idx) = lv_ordinal MOD lv_num_cols + 1.
    READ TABLE et_flat_records ASSIGNING <fs_rec> INDEX lv_rec_idx.
    IF sy-subrc = 0.
      READ TABLE mt_keyfig_map INTO DATA(ls_kf_col) INDEX lv_col_idx.
      IF sy-subrc = 0.
        ASSIGN COMPONENT ls_kf_col-field OF STRUCTURE <fs_rec> TO <fs_field>.
        IF sy-subrc = 0.
          TRY.
              PERFORM parse_numeric CHANGING <fs_cell>-value.
              <fs_field> = <fs_cell>-value.
            CATCH cx_root.
              CLEAR <fs_field>.
          ENDTRY.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  DATA: lt_workitems TYPE TABLE OF zotc_ma_wkitem,
        ls_workitems LIKE LINE OF lt_workitems.
  CLEAR: lt_workitems, ls_workitems.
  FIELD-SYMBOLS: <fs_flat_records> TYPE zsd_mgn_base_rpt.

  IF apply_wrkitem_data = 'X'.
    LOOP AT et_flat_records ASSIGNING <fs_flat_records>.
      MOVE <fs_flat_records>-vbelv TO <fs_flat_records>-vbeln.
      MOVE <fs_flat_records>-posnv TO <fs_flat_records>-posnr.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = <fs_flat_records>-vbeln
        IMPORTING
          output = <fs_flat_records>-vbeln.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = <fs_flat_records>-posnr
        IMPORTING
          output = <fs_flat_records>-posnr.
    ENDLOOP.

    SELECT * INTO TABLE lt_workitems
      FROM zotc_ma_wkitem
      FOR ALL ENTRIES IN et_flat_records
      WHERE vbeln = et_flat_records-vbeln
        AND posnr = et_flat_records-posnr.
    IF sy-subrc = 0.
      SORT et_flat_records BY vbeln posnr. "setup for binary search.
      LOOP AT lt_workitems INTO ls_workitems.
        READ TABLE et_flat_records ASSIGNING <fs_flat_records> WITH KEY vbeln = ls_workitems-vbeln posnr = ls_workitems-posnr BINARY SEARCH.
        IF sy-subrc = 0 AND <fs_flat_records> IS ASSIGNED.
          MOVE-CORRESPONDING ls_workitems TO <fs_flat_records>.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.

  return-type = 'S'.
  return-message = 'Successfully retrieved data'.

  IF clear_table = 'X' OR append_table = 'X'.
    IF et_flat_records[] IS NOT INITIAL.
      IF clear_table = 'X'.
        DELETE FROM zsd_mgn_base_rpt WHERE vbelv <> space.
        COMMIT WORK AND WAIT.
      ENDIF.
      IF append_table = 'X'.
        MODIFY zsd_mgn_base_rpt FROM TABLE et_flat_records.
        IF sy-subrc = 0.
          ev_records_inserted = sy-dbcnt.
          COMMIT WORK AND WAIT.
          ev_success = abap_true.
          ev_message = |Processed { ev_records_inserted } records|.
          return-type = 'S'.
          return-message = ev_message.
        ELSE.
          ev_success = abap_false.
          ev_message = |Failed to insert records|.
          return-type = 'E'.
          return-message = ev_message.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  CLEAR tbl_margin_data.
  CLEAR tbl_margin_data_small.

  IF output_data = 'X'.
    IF output_type = 'FULL'.
      tbl_margin_data[] = et_flat_records[].
    ELSEIF output_type = 'SMALL'.
      DATA: ls_margin_data_small LIKE LINE OF tbl_margin_data_small.
      LOOP AT et_flat_records INTO DATA(ls_flat_records).
        MOVE-CORRESPONDING ls_flat_records TO ls_margin_data_small.
        APPEND ls_margin_data_small TO tbl_margin_data_small.
      ENDLOOP.
    ENDIF.
  ENDIF.

  "======================================================================
  " S3 UPLOAD LOGIC
  "======================================================================
  IF s3_upload = 'X' AND et_flat_records[] IS NOT INITIAL.
    DATA: lv_s3_url        TYPE string,
          lv_s3_api_key    TYPE string,
          lv_s3_bucket     TYPE string,
          lv_s3_key        TYPE string,
          lv_file_content  TYPE string,
          lv_file_xstring  TYPE xstring,
          lv_content_type  TYPE string,
          lv_file_ext      TYPE string,
          lv_timestamp     TYPE string,
          lv_s3_message    TYPE string,
          lv_s3_status     TYPE char1,
          lv_http_status   TYPE i,
          lv_file_size     TYPE i,
          lv_start_time    TYPE timestampl,
          lv_end_time      TYPE timestampl,
          lv_duration_ms   TYPE i,
          ls_s3_log        TYPE zsd_mgn_s3_log.

    " Get timestamp for start
    GET TIME STAMP FIELD lv_start_time.

    " Read S3 configuration from TVARVC
    SELECT SINGLE low INTO @lv_s3_url
      FROM tvarvc
      WHERE name = @c_s3_url_tvarvc
        AND type = 'P'.

    SELECT SINGLE low INTO @lv_s3_api_key
      FROM tvarvc
      WHERE name = @c_s3_api_tvarvc
        AND type = 'P'.

    SELECT SINGLE low INTO @lv_s3_bucket
      FROM tvarvc
      WHERE name = @c_s3_bucket_tvarvc
        AND type = 'P'.

    IF lv_s3_url IS INITIAL.
      lv_s3_message = 'S3 URL not configured in TVARVC (' && c_s3_url_tvarvc && ')'.
      lv_s3_status = 'E'.
    ELSE.
      " Generate file name if not provided
      IF s3_file_name IS INITIAL.
        lv_timestamp = |{ sy-datum }{ sy-uzeit }|.
        CASE s3_file_format.
          WHEN 'JSON'.
            lv_file_ext = 'json'.
          WHEN 'FIXED'.
            lv_file_ext = 'txt'.
          WHEN OTHERS. " PIPE is default
            lv_file_ext = 'csv'.
        ENDCASE.
        lv_s3_key = |margin_data/{ sy-sysid }/{ sy-mandt }/margin_export_{ lv_timestamp }.{ lv_file_ext }|.
      ELSE.
        lv_s3_key = s3_file_name.
      ENDIF.

      " Convert table data to file format
      CASE s3_file_format.
        WHEN 'JSON'.
          PERFORM convert_to_json USING et_flat_records
                                  CHANGING lv_file_content.
          lv_content_type = 'application/json'.

        WHEN 'FIXED'.
          PERFORM convert_to_fixed_width USING et_flat_records
                                         CHANGING lv_file_content.
          lv_content_type = 'text/plain'.

        WHEN OTHERS. " PIPE is default
          PERFORM convert_to_pipe_delimited USING et_flat_records
                                            CHANGING lv_file_content.
          lv_content_type = 'text/csv'.
      ENDCASE.

      " Convert string to xstring (binary)
      PERFORM convert_string_to_xstring USING lv_file_content
                                        CHANGING lv_file_xstring.

      lv_file_size = xstrlen( lv_file_xstring ).

      " Upload to S3
      PERFORM upload_to_s3 USING lv_s3_url
                                 lv_s3_key
                                 lv_s3_api_key
                                 lv_file_xstring
                                 lv_content_type
                           CHANGING lv_http_status
                                    lv_s3_message
                                    lv_s3_status.
    ENDIF.

    " Get end timestamp and calculate duration
    GET TIME STAMP FIELD lv_end_time.
    lv_duration_ms = ( lv_end_time - lv_start_time ) * 1000.

    " Generate UUID for log entry
    TRY.
        DATA(lo_uuid) = cl_uuid_factory=>create_system_uuid( ).
        ev_s3_log_id = lo_uuid->create_uuid_c32( ).
      CATCH cx_uuid_error.
        ev_s3_log_id = |{ sy-datum }{ sy-uzeit }{ sy-uname }|.
    ENDTRY.

    " Create log entry
    CLEAR ls_s3_log.
    ls_s3_log-mandt         = sy-mandt.
    ls_s3_log-log_id        = ev_s3_log_id.
    ls_s3_log-upload_date   = sy-datum.
    ls_s3_log-upload_time   = sy-uzeit.
    ls_s3_log-username      = sy-uname.
    ls_s3_log-s3_bucket     = lv_s3_bucket.
    ls_s3_log-s3_key        = lv_s3_key.
    ls_s3_log-file_format   = s3_file_format.
    ls_s3_log-file_size     = lv_file_size.
    ls_s3_log-record_count  = lines( et_flat_records ).
    ls_s3_log-http_status   = lv_http_status.
    ls_s3_log-status        = lv_s3_status.
    ls_s3_log-message       = lv_s3_message.
    ls_s3_log-infoprovider  = i_infoprovider.
    ls_s3_log-query         = i_query.
    ls_s3_log-margin_analyst = margin_analyst.
    ls_s3_log-application   = application.
    ls_s3_log-duration_ms   = lv_duration_ms.
    ls_s3_log-correlation_id = ev_s3_log_id.

    INSERT zsd_mgn_s3_log FROM ls_s3_log.
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    " Update return message with S3 status
    IF lv_s3_status = 'S'.
      return-message = return-message && | | S3 upload successful: { lv_s3_key }|.
    ELSE.
      return-message = return-message && | | S3 upload failed: { lv_s3_message }|.
      " Don't change overall return type to E if data retrieval succeeded
    ENDIF.
  ENDIF.

  " Cleanup
  CLEAR: e_t_cell_data,
         e_t_axis_info,
         e_t_axis_chars,
         e_t_axis_attrs,
         e_t_axis_data_columns,
         e_t_axis_data_rows,
         e_t_axis_data_slicer,
         e_t_attr_data_rows,
         e_t_attr_data_columns,
         e_t_text_symbols,
         e_t_messages.

  REFRESH: e_t_cell_data,
           e_t_axis_info,
           e_t_axis_chars,
           e_t_axis_attrs,
           e_t_axis_data_columns,
           e_t_axis_data_rows,
           e_t_axis_data_slicer,
           e_t_attr_data_rows,
           e_t_attr_data_columns,
           e_t_text_symbols,
           e_t_messages.

ENDFUNCTION.

*&---------------------------------------------------------------------*
*& Form clean_sap_value
*&---------------------------------------------------------------------*
FORM clean_sap_value CHANGING iv_value.
  DATA: rv_clean TYPE string.
  DATA(lv_str) = CONV string( iv_value ).
  IF lv_str = '#' OR lv_str IS INITIAL.
    rv_clean = ''.
  ELSE.
    rv_clean = condense( lv_str ).
  ENDIF.
  iv_value = rv_clean.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form parse_numeric
*&---------------------------------------------------------------------*
FORM parse_numeric CHANGING iv_value.
  PERFORM clean_sap_value USING iv_value.
  DATA lv_str TYPE string.
  DATA rv_num TYPE string.
  lv_str = iv_value.
  IF lv_str IS INITIAL.
    rv_num = 0.
    iv_value = rv_num.
    RETURN.
  ENDIF.
  REPLACE ALL OCCURRENCES OF '$' IN lv_str WITH ''.
  REPLACE ALL OCCURRENCES OF ',' IN lv_str WITH ''.
  CONDENSE lv_str NO-GAPS.
  TRY.
      rv_num = lv_str.
    CATCH cx_sy_conversion_no_number.
      rv_num = 0.
  ENDTRY.
  iv_value = rv_num.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form convert_to_json
*&---------------------------------------------------------------------*
*& Converts internal table to JSON format
*&---------------------------------------------------------------------*
FORM convert_to_json USING it_data TYPE TABLE
                     CHANGING cv_json TYPE string.

  DATA: lo_json_writer TYPE REF TO cl_sxml_string_writer,
        lv_json_xstring TYPE xstring.

  TRY.
      " Use standard SAP JSON serialization
      cv_json = /ui2/cl_json=>serialize(
        data        = it_data
        compress    = abap_false
        pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
    CATCH cx_root INTO DATA(lx_error).
      " Fallback: Manual JSON construction
      PERFORM convert_to_json_manual USING it_data
                                     CHANGING cv_json.
  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form convert_to_json_manual
*&---------------------------------------------------------------------*
*& Manual JSON conversion fallback
*&---------------------------------------------------------------------*
FORM convert_to_json_manual USING it_data TYPE TABLE
                            CHANGING cv_json TYPE string.

  DATA: lv_line     TYPE string,
        lv_fieldval TYPE string,
        lo_struct   TYPE REF TO cl_abap_structdescr,
        lt_fields   TYPE abap_compdescr_tab.

  FIELD-SYMBOLS: <fs_record> TYPE any,
                 <fs_field>  TYPE any,
                 <fs_comp>   TYPE abap_compdescr.

  cv_json = '['.
  DATA(lv_first_rec) = abap_true.

  LOOP AT it_data ASSIGNING <fs_record>.
    IF lv_first_rec = abap_false.
      cv_json = cv_json && ','.
    ENDIF.
    lv_first_rec = abap_false.

    cv_json = cv_json && '{'.

    " Get structure components
    lo_struct ?= cl_abap_typedescr=>describe_by_data( <fs_record> ).
    lt_fields = lo_struct->components.

    DATA(lv_first_fld) = abap_true.
    LOOP AT lt_fields ASSIGNING <fs_comp>.
      ASSIGN COMPONENT <fs_comp>-name OF STRUCTURE <fs_record> TO <fs_field>.
      IF sy-subrc = 0.
        IF lv_first_fld = abap_false.
          cv_json = cv_json && ','.
        ENDIF.
        lv_first_fld = abap_false.

        lv_fieldval = <fs_field>.
        " Escape special characters in JSON
        REPLACE ALL OCCURRENCES OF '\' IN lv_fieldval WITH '\\'.
        REPLACE ALL OCCURRENCES OF '"' IN lv_fieldval WITH '\"'.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_fieldval WITH '\n'.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_fieldval WITH '\n'.

        " Convert field name to lowercase
        DATA(lv_fname) = to_lower( <fs_comp>-name ).
        cv_json = cv_json && |"{ lv_fname }":"{ lv_fieldval }"|.
      ENDIF.
    ENDLOOP.

    cv_json = cv_json && '}'.
  ENDLOOP.

  cv_json = cv_json && ']'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form convert_to_pipe_delimited
*&---------------------------------------------------------------------*
*& Converts internal table to pipe-delimited format
*&---------------------------------------------------------------------*
FORM convert_to_pipe_delimited USING it_data TYPE TABLE
                               CHANGING cv_content TYPE string.

  DATA: lv_line     TYPE string,
        lv_fieldval TYPE string,
        lo_struct   TYPE REF TO cl_abap_structdescr,
        lt_fields   TYPE abap_compdescr_tab.

  FIELD-SYMBOLS: <fs_record> TYPE any,
                 <fs_field>  TYPE any,
                 <fs_comp>   TYPE abap_compdescr.

  CLEAR cv_content.

  " Get structure components from first record for header
  READ TABLE it_data ASSIGNING <fs_record> INDEX 1.
  IF sy-subrc = 0.
    lo_struct ?= cl_abap_typedescr=>describe_by_data( <fs_record> ).
    lt_fields = lo_struct->components.

    " Build header line
    DATA(lv_first) = abap_true.
    LOOP AT lt_fields ASSIGNING <fs_comp>.
      IF lv_first = abap_false.
        lv_line = lv_line && '|'.
      ENDIF.
      lv_first = abap_false.
      lv_line = lv_line && <fs_comp>-name.
    ENDLOOP.
    cv_content = lv_line && cl_abap_char_utilities=>cr_lf.
  ENDIF.

  " Build data lines
  LOOP AT it_data ASSIGNING <fs_record>.
    CLEAR lv_line.
    lv_first = abap_true.

    LOOP AT lt_fields ASSIGNING <fs_comp>.
      ASSIGN COMPONENT <fs_comp>-name OF STRUCTURE <fs_record> TO <fs_field>.
      IF sy-subrc = 0.
        IF lv_first = abap_false.
          lv_line = lv_line && '|'.
        ENDIF.
        lv_first = abap_false.

        lv_fieldval = <fs_field>.
        " Remove pipe characters from values to avoid delimiter conflicts
        REPLACE ALL OCCURRENCES OF '|' IN lv_fieldval WITH ' '.
        CONDENSE lv_fieldval.
        lv_line = lv_line && lv_fieldval.
      ENDIF.
    ENDLOOP.

    cv_content = cv_content && lv_line && cl_abap_char_utilities=>cr_lf.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form convert_to_fixed_width
*&---------------------------------------------------------------------*
*& Converts internal table to fixed-width format
*&---------------------------------------------------------------------*
FORM convert_to_fixed_width USING it_data TYPE TABLE
                            CHANGING cv_content TYPE string.

  DATA: lv_line     TYPE string,
        lv_fieldval TYPE string,
        lv_padded   TYPE string,
        lo_struct   TYPE REF TO cl_abap_structdescr,
        lt_fields   TYPE abap_compdescr_tab.

  FIELD-SYMBOLS: <fs_record> TYPE any,
                 <fs_field>  TYPE any,
                 <fs_comp>   TYPE abap_compdescr.

  CLEAR cv_content.

  " Get structure components from first record
  READ TABLE it_data ASSIGNING <fs_record> INDEX 1.
  IF sy-subrc = 0.
    lo_struct ?= cl_abap_typedescr=>describe_by_data( <fs_record> ).
    lt_fields = lo_struct->components.

    " Build header line with fixed widths
    CLEAR lv_line.
    LOOP AT lt_fields ASSIGNING <fs_comp>.
      " Pad field name to defined length
      lv_padded = <fs_comp>-name.
      PERFORM pad_to_length USING <fs_comp>-length
                            CHANGING lv_padded.
      lv_line = lv_line && lv_padded.
    ENDLOOP.
    cv_content = lv_line && cl_abap_char_utilities=>cr_lf.
  ENDIF.

  " Build data lines
  LOOP AT it_data ASSIGNING <fs_record>.
    CLEAR lv_line.

    LOOP AT lt_fields ASSIGNING <fs_comp>.
      ASSIGN COMPONENT <fs_comp>-name OF STRUCTURE <fs_record> TO <fs_field>.
      IF sy-subrc = 0.
        lv_fieldval = <fs_field>.
        " Remove line breaks
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_fieldval WITH ' '.
        REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_fieldval WITH ' '.
        " Pad to field length
        PERFORM pad_to_length USING <fs_comp>-length
                              CHANGING lv_fieldval.
        lv_line = lv_line && lv_fieldval.
      ENDIF.
    ENDLOOP.

    cv_content = cv_content && lv_line && cl_abap_char_utilities=>cr_lf.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form pad_to_length
*&---------------------------------------------------------------------*
*& Pads or truncates string to specified length
*&---------------------------------------------------------------------*
FORM pad_to_length USING iv_length TYPE i
                   CHANGING cv_value TYPE string.

  DATA: lv_len TYPE i.

  lv_len = strlen( cv_value ).

  IF lv_len > iv_length.
    " Truncate
    cv_value = cv_value(iv_length).
  ELSEIF lv_len < iv_length.
    " Pad with spaces
    DO ( iv_length - lv_len ) TIMES.
      cv_value = cv_value && ' '.
    ENDDO.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form convert_string_to_xstring
*&---------------------------------------------------------------------*
*& Converts string to xstring using UTF-8 encoding
*&---------------------------------------------------------------------*
FORM convert_string_to_xstring USING iv_string TYPE string
                               CHANGING cv_xstring TYPE xstring.

  DATA: lo_conv TYPE REF TO cl_abap_conv_out_ce.

  TRY.
      lo_conv = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
      lo_conv->convert( EXPORTING data = iv_string
                        IMPORTING buffer = cv_xstring ).
    CATCH cx_root.
      " Fallback conversion
      cv_xstring = cl_bcs_convert=>string_to_xstring( iv_string ).
  ENDTRY.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form upload_to_s3
*&---------------------------------------------------------------------*
*& Uploads file content to S3 via HTTP PUT
*&---------------------------------------------------------------------*
FORM upload_to_s3 USING iv_url TYPE string
                        iv_s3_key TYPE string
                        iv_api_key TYPE string
                        iv_content TYPE xstring
                        iv_content_type TYPE string
                  CHANGING cv_http_status TYPE i
                           cv_message TYPE string
                           cv_status TYPE char1.

  DATA: lo_client          TYPE REF TO if_http_client,
        lv_full_url        TYPE string,
        lv_http_error      TYPE string,
        lv_subrc           TYPE sysubrc,
        lv_response        TYPE string.

  " Build full URL
  lv_full_url = iv_url.
  IF iv_url CP '*/' .
    lv_full_url = iv_url && iv_s3_key.
  ELSE.
    lv_full_url = iv_url && '/' && iv_s3_key.
  ENDIF.
  CONDENSE lv_full_url NO-GAPS.

  " Create HTTP client
  CALL METHOD cl_http_client=>create_by_url
    EXPORTING
      url                = lv_full_url
    IMPORTING
      client             = lo_client
    EXCEPTIONS
      argument_not_found = 1
      plugin_not_active  = 2
      internal_error     = 3
      OTHERS             = 4.

  IF sy-subrc <> 0.
    cv_status = 'E'.
    cv_message = |HTTP client creation failed for URL: { lv_full_url }|.
    cv_http_status = 0.
    RETURN.
  ENDIF.

  " Set request method to PUT
  lo_client->request->set_header_field(
    name  = '~request_method'
    value = 'PUT' ).

  " Set Content-Type header
  lo_client->request->set_header_field(
    name  = 'Content-Type'
    value = iv_content_type ).

  " Set Cache-Control
  lo_client->request->set_header_field(
    name  = 'Cache-Control'
    value = 'no-cache' ).

  " Set API key if provided
  IF iv_api_key IS NOT INITIAL.
    lo_client->request->set_header_field(
      name  = 'X-API-Key'
      value = iv_api_key ).
  ENDIF.

  " Set request body
  lo_client->request->set_data( iv_content ).

  " Disable logon popup
  lo_client->propertytype_logon_popup = lo_client->co_disabled.

  " Send request
  CALL METHOD lo_client->send
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      OTHERS                     = 3.

  IF sy-subrc <> 0.
    CALL METHOD lo_client->get_last_error
      IMPORTING
        code    = lv_subrc
        message = lv_http_error.
    cv_status = 'E'.
    cv_message = |HTTP send failed: { lv_http_error }|.
    cv_http_status = 0.
    lo_client->close( ).
    RETURN.
  ENDIF.

  " Receive response
  CALL METHOD lo_client->receive
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      OTHERS                     = 4.

  IF sy-subrc <> 0.
    CASE sy-subrc.
      WHEN 1.
        cv_message = 'HTTP communication failure'.
      WHEN 2.
        cv_message = 'HTTP invalid state'.
      WHEN 3.
        cv_message = 'HTTP processing failed'.
      WHEN OTHERS.
        cv_message = 'HTTP receive error'.
    ENDCASE.
    cv_status = 'E'.
    cv_http_status = 0.
    lo_client->close( ).
    RETURN.
  ENDIF.

  " Get response status
  lo_client->response->get_status(
    IMPORTING
      code   = cv_http_status
      reason = lv_http_error ).

  " Check for success (200, 201, 204 are typical success codes for PUT)
  IF cv_http_status >= 200 AND cv_http_status < 300.
    cv_status = 'S'.
    cv_message = |Upload successful (HTTP { cv_http_status })|.
  ELSE.
    cv_status = 'E'.
    lv_response = lo_client->response->get_cdata( ).
    cv_message = |Upload failed: HTTP { cv_http_status } - { lv_http_error }|.
    IF lv_response IS NOT INITIAL AND strlen( lv_response ) < 200.
      cv_message = cv_message && | Response: { lv_response }|.
    ENDIF.
  ENDIF.

  " Close connection
  lo_client->close( ).

ENDFORM.
