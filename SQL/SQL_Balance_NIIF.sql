--SELECT * FROM X_BALANCE_CC('01', '', 2023, 01) WHERE SALDO_INICIAL != 0 OR CREDITO != 0 OR DEBITO != 0 ORDER BY CODIGOCTA, CODCC
--SELECT * FROM SALDCONTNI WHERE ANO = 2023 AND PERIODO = 01 AND CODIGOCTA LIKE '1125%'
USE [MARISTAS]

DROP FUNCTION X_BALANCE_CC;
DROP FUNCTION X_SALDOCUENTA_NIIF_CC;
DROP FUNCTION X_DEBITO_CREDITO_CC;
DROP FUNCTION X_SALDOINICIAL_TABLA;

/*GO
CREATE NONCLUSTERED INDEX [<IDX_CREDITO_DEBITO, sysname,>]
ON [dbo].[SALDCONTNI] ([ANO],[PERIODO],[CODCC])
INCLUDE ([CREDITO],[DEBITO])

GO
CREATE NONCLUSTERED INDEX [<IDX_CREDITO, sysname,>]
ON [dbo].[SALDCONTNI] ([CODCC],[CODIGOCTA])
INCLUDE ([CREDITO])

GO
CREATE NONCLUSTERED INDEX [<IDX_DEBITO, sysname,>]
ON [dbo].[SALDCONTNI] ([CODCC],[CODIGOCTA])
INCLUDE ([DEBITO])

GO
CREATE NONCLUSTERED INDEX [<descripcio, sysname,>]
ON [dbo].[CUENTASNIF] ([TIPOCUENTA])
INCLUDE ([DESCRIPCIO])

GO
CREATE NONCLUSTERED INDEX [<IDX_CODCC, sysname,>]
ON [dbo].[SALDCONTNI] ([CODCC])
INCLUDE ([CREDITO],[DEBITO])
GO

CREATE NONCLUSTERED INDEX [<IDX_CRED_DEB, sysname,>]
ON [dbo].[SALDCONTNI] ([CODCC],[CODIGOCTA])
INCLUDE ([CREDITO],[DEBITO])
GO
*/

GO
CREATE FUNCTION [dbo].[X_SALDOCUENTA_NIIF_CC]
(
@fecha date,
@cuenta varchar(20),
@codcc varchar(20)
)
RETURNS NUMERIC(17,2)
AS
	BEGIN
	DECLARE @valor NUMERIC(17,2)
	SELECT @valor = (
	SELECT ISNULL(SUM (TEMP.DEBITO) - SUM(TEMP.CREDITO), 0) SALDO_INICIAL FROM
	(
		SELECT
		DATEFROMPARTS(CAST(ANO AS INT),
		CASE WHEN PERIODO = 13 THEN 12 ELSE CAST (PERIODO AS INT) END, 1) FECHA, *
		FROM SALDCONTNI) TEMP
		WHERE TEMP.CODIGOCTA LIKE RTRIM(@cuenta) + '%' AND TEMP.CODCC LIKE RTRIM(@codcc) + '%' AND TEMP.FECHA < @fecha
	)
	RETURN @valor
END

GO

CREATE FUNCTION [dbo].[X_SALDOINICIAL_TABLA]
(
	@fecha date,
	@cuenta varchar(20),
	@codcc varchar(20)
)
RETURNS TABLE
AS
RETURN
(
	SELECT
	CODIGOCTA,
	CODCC,
	ISNULL(SUM(DEBITO) - SUM(CREDITO), 0) SALDO_INICIAL
	FROM 
	SALDCONTNI
	WHERE
	DATEFROMPARTS(CAST(ANO AS INT), CASE WHEN PERIODO = 13 THEN 12 ELSE CAST (PERIODO AS INT) END, 1) < @fecha AND
	CODIGOCTA LIKE RTRIM(@cuenta) + '%' AND
	CODCC LIKE RTRIM(@codcc) + '%'
	GROUP BY 
	CODIGOCTA, CODCC
)


GO

CREATE FUNCTION [dbo].[X_DEBITO_CREDITO_CC]
(
	@codcc varchar(20),
	@codigocta varchar(20),
	@ano numeric,
	@periodo numeric
)
RETURNS TABLE
AS
RETURN
	(
	SELECT
	CUENTASNIF.CODIGOCTA,
	ISNULL(SUM(CREDITO), 0) CREDITO,
	ISNULL(SUM(DEBITO), 0) DEBITO
	FROM
	SALDCONTNI,
	CUENTASNIF
	WHERE 
	CUENTASNIF.CODIGOCTA LIKE RTRIM(@codigocta) + '%' AND
	SALDCONTNI.CODIGOCTA LIKE RTRIM(CUENTASNIF.CODIGOCTA) + '%' AND
	CODCC LIKE RTRIM(@codcc) + '%' AND
	ANO = @ano AND
	PERIODO = @periodo	
	GROUP BY CUENTASNIF.CODIGOCTA
)

GO

CREATE FUNCTION [dbo].[X_BALANCE_CC]
(
	@codcc varchar(20),
	@codigocta varchar(20),
	@ano numeric,
	@periodo numeric
)
RETURNS TABLE 
AS
RETURN
(
	SELECT 
	SALDCONTNI.CODIGOCTA, 
	CUENTASNIF.DESCRIPCIO NOMBRECTA,
	SALDCONTNI.CODCC,
	CENTCOS.NOMBRE CENTRO_COSTOS,
	ISNULL(SALDOCUENTA.SALDO_INICIAL, 0) SALDO_INICIAL,
	--dbo.X_SALDOCUENTA_NIIF_CC(DATEFROMPARTS(CAST(@ano AS INT), CAST(@periodo AS INT), 1), SALDCONTNI.CODIGOCTA, SALDCONTNI.CODCC) SALDO_INICIAL,
	SUM(CASE WHEN PERIODO = @PERIODO AND ANO = @ANO THEN DEBITO ELSE 0 END) DEBITO, 
	SUM(CASE WHEN PERIODO = @PERIODO AND ANO = @ANO THEN CREDITO ELSE 0 END) CREDITO,
	1 AUXILIAR
	FROM 
	SALDCONTNI 
	LEFT OUTER JOIN X_SALDOINICIAL_TABLA(DATEFROMPARTS(@ano, @periodo, 1), @codigocta, @codcc) SALDOCUENTA
	ON 
	(SALDOCUENTA.CODCC = SALDCONTNI.CODCC AND	
	SALDOCUENTA.CODIGOCTA = SALDCONTNI.CODIGOCTA),
	CUENTASNIF,
	CENTCOS	
	WHERE 
	CENTCOS.CODCC = SALDCONTNI.CODCC AND
	SALDCONTNI.CODCC LIKE RTRIM(@codcc) + '%' AND
	SALDCONTNI.CODIGOCTA LIKE RTRIM(@codigocta) + '%' AND
	DATEFROMPARTS(CAST(ANO AS INT), CASE WHEN PERIODO = 13 THEN 12 ELSE CAST (PERIODO AS INT) END, 1) <= DATEFROMPARTS(CAST(@ano AS INT), CAST(@periodo AS INT), 1) AND
	--ANO = @ano AND PERIODO = @periodo AND
	CUENTASNIF.CODIGOCTA = SALDCONTNI.CODIGOCTA --AND
	--SALDOCUENTA.CODCC = SALDCONTNI.CODCC AND	
	--SALDOCUENTA.CODIGOCTA = SALDCONTNI.CODIGOCTA
	GROUP BY 
	SALDCONTNI.CODIGOCTA, SALDCONTNI.CODCC, SALDOCUENTA.SALDO_INICIAL, CENTCOS.NOMBRE, CUENTASNIF.DESCRIPCIO
	UNION ALL
	SELECT 
	C.CODIGOCTA,
	C.DESCRIPCIO,
	'',
	'',
	dbo.X_SALDOCUENTA_NIIF_CC(DATEFROMPARTS(CAST(@ano AS INT), CAST(@periodo AS INT), 1), C.CODIGOCTA, RTRIM(@codcc)) SALDO_INICIAL,
	ISNULL(TOTALES.DEBITO, 0) DEBITO,
	ISNULL(TOTALES.CREDITO, 0) CREDITO,
	0
	FROM 
	CUENTASNIF C
	LEFT OUTER JOIN
	X_DEBITO_CREDITO_CC(@codcc, @codigocta, @ano, @periodo) TOTALES ON
	TOTALES.CODIGOCTA = C.CODIGOCTA
	WHERE 
	TIPOCUENTA = 0 AND
	C.CODIGOCTA LIKE RTRIM(@CODIGOCTA) + '%' 	
)
