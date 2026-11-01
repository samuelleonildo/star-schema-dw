-- ============================================================================
-- EXTENSAO DOS ESQUEMAS COM OS METADADOS DO TOPICO 8 DO PDF + POVOAMENTO
-- Schemas: dm_aluno_prof e dm_prof
--
-- ORDEM DE EXECUCAO:
--   1) criacao dos schemas (seus dois DDLs)
--   2) populate_tables.sql
--   3) ESTE SCRIPT (uma unica vez, numa unica sessao)
--   4) consultas_analiticas_dm.sql
-- Para refazer: rode de novo o passo 2 (ele limpa tambem as tabelas novas
-- via CASCADE) e depois este script.
--
-- O QUE ENTRA (topico 8 do PDF e itens do topico 7 usados pelas consultas):
--   Aluno      : n da tentativa (fato), situacao de matricula por semestre
--                (fato_matricula_periodo), atividades extracurriculares,
--                auxilio (inicio/fim/tipo/valor), distancia/tempo de deslocamento
--   Disciplina : vagas ofertadas por turma; pre-requisitos (consultas 1.13)
--   Professor  : regime de trabalho e titulacao; avaliacao docente
--   Curso      : conceito ENADE
-- Os valores sao sinteticos (aleatorios com semente fixa), coerentes com os
-- dados ja gerados.
-- ============================================================================

SELECT setseed(0.2027);

-- ----------------------------------------------------------------------------
-- A. COLUNAS NOVAS EM TABELAS EXISTENTES
-- ----------------------------------------------------------------------------
ALTER TABLE dm_aluno_prof.dim_curso
    ADD COLUMN IF NOT EXISTS conceito_enade SMALLINT CHECK (conceito_enade BETWEEN 1 AND 5);
ALTER TABLE dm_prof.dim_curso
    ADD COLUMN IF NOT EXISTS conceito_enade SMALLINT CHECK (conceito_enade BETWEEN 1 AND 5);

ALTER TABLE dm_aluno_prof.dim_professor
    ADD COLUMN IF NOT EXISTS regime_trabalho VARCHAR(10),      -- DE, 40h, 20h
    ADD COLUMN IF NOT EXISTS titulacao       VARCHAR(30);
ALTER TABLE dm_prof.dim_professor
    ADD COLUMN IF NOT EXISTS regime_trabalho VARCHAR(10),
    ADD COLUMN IF NOT EXISTS titulacao       VARCHAR(30);

ALTER TABLE dm_aluno_prof.dim_aluno
    ADD COLUMN IF NOT EXISTS distancia_campus_km    NUMERIC(5,1),
    ADD COLUMN IF NOT EXISTS tempo_deslocamento_min INTEGER;

ALTER TABLE dm_aluno_prof.dim_turma_disciplina
    ADD COLUMN IF NOT EXISTS vagas_ofertadas INTEGER;
ALTER TABLE dm_prof.dim_turma_disciplina
    ADD COLUMN IF NOT EXISTS vagas_ofertadas INTEGER;

ALTER TABLE dm_aluno_prof.fato_aluno_em_disciplina
    ADD COLUMN IF NOT EXISTS nr_tentativa INTEGER NOT NULL DEFAULT 1;

-- ----------------------------------------------------------------------------
-- B. TABELAS NOVAS
-- ----------------------------------------------------------------------------

-- Situacao de matricula por semestre (grao: aluno x semestre)
CREATE TABLE IF NOT EXISTS dm_aluno_prof.fato_matricula_periodo (
    tempo_id        INTEGER     NOT NULL,   -- data de referencia do semestre (15/06 ou 15/12)
    aluno_id        INTEGER     NOT NULL,
    curso_id        INTEGER     NOT NULL,
    semestre_curso  INTEGER     NOT NULL,   -- 1 = semestre de ingresso
    situacao        VARCHAR(20) NOT NULL,   -- Ativo | Trancado | Cancelado | Formado
    CONSTRAINT pk_fato_matricula_periodo PRIMARY KEY (tempo_id, aluno_id),
    CONSTRAINT fk_fmp_tempo FOREIGN KEY (tempo_id) REFERENCES dm_aluno_prof.dim_data (tempo_id),
    CONSTRAINT fk_fmp_aluno FOREIGN KEY (aluno_id) REFERENCES dm_aluno_prof.dim_aluno (aluno_id),
    CONSTRAINT fk_fmp_curso FOREIGN KEY (curso_id) REFERENCES dm_aluno_prof.dim_curso (curso_id)
);

-- Auxilio estudantil com inicio, fim, tipo e valor
CREATE TABLE IF NOT EXISTS dm_aluno_prof.aluno_auxilio (
    aluno_id      INTEGER       NOT NULL,
    tipo_auxilio  VARCHAR(50)   NOT NULL,
    valor_mensal  NUMERIC(8,2)  NOT NULL,
    data_inicio   DATE          NOT NULL,
    data_fim      DATE,                      -- NULL = auxilio vigente
    CONSTRAINT pk_aluno_auxilio PRIMARY KEY (aluno_id, data_inicio),
    CONSTRAINT fk_auxilio_aluno FOREIGN KEY (aluno_id) REFERENCES dm_aluno_prof.dim_aluno (aluno_id)
);

-- Atividades extracurriculares
CREATE TABLE IF NOT EXISTS dm_aluno_prof.aluno_atividade_extra (
    atividade_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aluno_id        INTEGER      NOT NULL,
    tipo_atividade  VARCHAR(50)  NOT NULL,
    data_inicio     DATE         NOT NULL,
    data_fim        DATE,
    ch_semanal      INTEGER,
    CONSTRAINT fk_atividade_aluno FOREIGN KEY (aluno_id) REFERENCES dm_aluno_prof.dim_aluno (aluno_id)
);

-- Pre-requisitos entre disciplinas
CREATE TABLE IF NOT EXISTS dm_aluno_prof.disciplina_prerequisito (
    disciplina_id    INTEGER NOT NULL,
    prerequisito_id  INTEGER NOT NULL,
    CONSTRAINT pk_disciplina_prerequisito PRIMARY KEY (disciplina_id, prerequisito_id),
    CONSTRAINT fk_prereq_disc FOREIGN KEY (disciplina_id)   REFERENCES dm_aluno_prof.dim_disciplina (disciplina_id),
    CONSTRAINT fk_prereq_req  FOREIGN KEY (prerequisito_id) REFERENCES dm_aluno_prof.dim_disciplina (disciplina_id)
);

-- Avaliacao docente pelos alunos (nota 1 a 5 por turma e professor)
CREATE TABLE IF NOT EXISTS dm_prof.avaliacao_docente (
    turma_id          INTEGER      NOT NULL,
    professor_id      INTEGER      NOT NULL,
    tempo_id          INTEGER      NOT NULL,
    nota_media        NUMERIC(3,2) NOT NULL CHECK (nota_media BETWEEN 1 AND 5),
    qtd_respondentes  INTEGER      NOT NULL,
    CONSTRAINT pk_avaliacao_docente PRIMARY KEY (turma_id, professor_id),
    CONSTRAINT fk_aval_turma FOREIGN KEY (turma_id)     REFERENCES dm_prof.dim_turma_disciplina (turma_id),
    CONSTRAINT fk_aval_prof  FOREIGN KEY (professor_id) REFERENCES dm_prof.dim_professor (professor_id),
    CONSTRAINT fk_aval_tempo FOREIGN KEY (tempo_id)     REFERENCES dm_prof.dim_data (tempo_id)
);

-- Protecao contra execucao dupla (a extensao remove/insere linhas na fato)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM dm_aluno_prof.fato_matricula_periodo) THEN
        RAISE EXCEPTION 'Extensao ja aplicada. Rode o povoamento novamente antes de reaplicar.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- C. POVOAMENTO DOS METADADOS
-- ----------------------------------------------------------------------------

-- C.1 Conceito ENADE (2 a 5)
UPDATE dm_aluno_prof.dim_curso SET conceito_enade = 2 + (curso_id * 5) % 4;
UPDATE dm_prof.dim_curso p SET conceito_enade = a.conceito_enade
  FROM dm_aluno_prof.dim_curso a WHERE a.curso_id = p.curso_id;

-- C.2 Regime de trabalho e titulacao dos professores
UPDATE dm_aluno_prof.dim_professor SET
    regime_trabalho = CASE WHEN professor_id % 10 < 7 THEN 'DE' WHEN professor_id % 10 < 9 THEN '40h' ELSE '20h' END,
    titulacao       = CASE WHEN professor_id % 10 < 6 THEN 'Doutorado' WHEN professor_id % 10 < 8 THEN 'Pós-Doutorado' ELSE 'Mestrado' END;
UPDATE dm_prof.dim_professor p SET regime_trabalho = a.regime_trabalho, titulacao = a.titulacao
  FROM dm_aluno_prof.dim_professor a WHERE a.professor_id = p.professor_id;

-- C.3 Distancia/tempo de deslocamento (consistente por bairro e campus)
UPDATE dm_aluno_prof.dim_aluno a
   SET distancia_campus_km = ROUND((2 + (ABS(hashtext(c.campi || a.bairro_residencia)) % 220) / 10.0 + (a.aluno_id % 5) * 0.3)::numeric, 1)
  FROM dm_aluno_prof.dim_curso c
 WHERE c.curso_id = a.curso_id;

UPDATE dm_aluno_prof.dim_aluno a
   SET tempo_deslocamento_min =
       ROUND(8 + a.distancia_campus_km * (CASE WHEN c.campi = 'Campus Recife' THEN 3.2 ELSE 2.2 END) + a.aluno_id % 10)::int
  FROM dm_aluno_prof.dim_curso c
 WHERE c.curso_id = a.curso_id;

-- C.4 Pre-requisitos: disciplina obrigatoria exige a obrigatoria 3 posicoes antes, no mesmo curso
INSERT INTO dm_aluno_prof.disciplina_prerequisito (disciplina_id, prerequisito_id)
SELECT d.disciplina_id, p.disciplina_id
FROM dm_aluno_prof.dim_disciplina d
JOIN dm_aluno_prof.dim_disciplina p
  ON p.fk_curso = d.fk_curso AND p.disciplina_id = d.disciplina_id - 3
WHERE d.tipo = 'Obrigatória' AND p.tipo = 'Obrigatória' AND p.periodo < d.periodo;

-- C.5 Apoio: indice de semestre (0 = 2023.1 ... 6 = 2026.1) por aluno
CREATE TEMP TABLE tmp_al AS
SELECT aluno_id, curso_id, tipo_evasao,
       (ano_ingresso - 2023) * 2 + semestre_ingresso - 1 AS e,
       CASE WHEN ano_evasao IS NULL THEN NULL
            ELSE (ano_evasao - 2023) * 2 + semestre_evasao - 1 END AS ev
FROM dm_aluno_prof.dim_aluno;

-- C.6 Trancamentos (~3% dos semestres entre ingresso e evasao).
--     Num semestre trancado nao ha matricula em disciplinas: remove-se da fato.
CREATE TEMP TABLE tmp_tranc AS
SELECT a.aluno_id, s.m AS sem,
       (make_date(2023 + s.m / 2, CASE WHEN s.m % 2 = 0 THEN 6 ELSE 12 END, 15) - DATE '2023-01-01') + 1 AS tempo_id
FROM tmp_al a
CROSS JOIN LATERAL generate_series(a.e + 1, LEAST(6, COALESCE(a.ev, 7) - 1)) AS s(m)
WHERE random() < 0.03;

DELETE FROM dm_aluno_prof.fato_aluno_em_disciplina f
 USING tmp_tranc t
 WHERE f.aluno_id = t.aluno_id AND f.tempo_id = t.tempo_id;

-- C.7 Auxilio estudantil: so quem tem assistencia_estudantil <> 'Nenhum';
--     comeca 0 a 2 semestres apos o ingresso e termina na evasao (se houver).
INSERT INTO dm_aluno_prof.aluno_auxilio (aluno_id, tipo_auxilio, valor_mensal, data_inicio, data_fim)
SELECT a.aluno_id,
       a.assistencia_estudantil,
       CASE a.assistencia_estudantil WHEN 'Bolsa Permanência' THEN 600.00 ELSE 450.00 END,
       make_date(2023 + x.sm / 2, CASE WHEN x.sm % 2 = 0 THEN 3 ELSE 9 END, 1),
       CASE WHEN al.ev IS NULL THEN NULL
            ELSE make_date(2023 + al.ev / 2, CASE WHEN al.ev % 2 = 0 THEN 6 ELSE 12 END, CASE WHEN al.ev % 2 = 0 THEN 30 ELSE 31 END) END
FROM dm_aluno_prof.dim_aluno a
JOIN tmp_al al ON al.aluno_id = a.aluno_id
CROSS JOIN LATERAL (SELECT LEAST(al.e + (a.aluno_id % 3), COALESCE(al.ev, 6)) AS sm) x
WHERE a.assistencia_estudantil <> 'Nenhum';

-- C.8 Atividades extracurriculares (~35% dos alunos)
INSERT INTO dm_aluno_prof.aluno_atividade_extra (aluno_id, tipo_atividade, data_inicio, data_fim, ch_semanal)
SELECT al.aluno_id,
       (ARRAY['Iniciação Científica','Monitoria','Extensão','Estágio','Empresa Júnior','Atlética/Esportes'])[1 + al.aluno_id % 6],
       ini.d,
       CASE WHEN al.ev IS NOT NULL THEN
                 make_date(2023 + al.ev / 2, CASE WHEN al.ev % 2 = 0 THEN 6 ELSE 12 END, CASE WHEN al.ev % 2 = 0 THEN 30 ELSE 31 END)
            WHEN al.aluno_id % 4 = 0 AND ini.d + 365 <= DATE '2026-06-30' THEN ini.d + 365
            ELSE NULL END,
       (ARRAY[4, 8, 12, 20])[1 + al.aluno_id % 4]
FROM tmp_al al
CROSS JOIN LATERAL (SELECT LEAST(al.e + 1 + al.aluno_id % 2, 6) AS sm) x
CROSS JOIN LATERAL (SELECT make_date(2023 + x.sm / 2, CASE WHEN x.sm % 2 = 0 THEN 3 ELSE 9 END, 1) AS d) ini
WHERE al.aluno_id % 100 < 35
  AND (al.ev IS NULL OR x.sm <= al.ev);

-- C.9 Reprovacao e REPETICAO da disciplina (n da tentativa).
--     Quem reprova e segue ativo cursa de novo no proximo semestre em que a
--     disciplina e ofertada (70% dos casos), ate 3 tentativas.
CREATE TEMP TABLE tmp_tt AS
SELECT DISTINCT f.turma_id, f.disciplina_id, f.tempo_id,
       d.ano * 2 + d.semestre - 4047 AS sem
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN dm_aluno_prof.dim_data d ON d.tempo_id = f.tempo_id;

DO $$
DECLARE t int;
BEGIN
  FOR t IN 1..2 LOOP
    WITH cand AS MATERIALIZED (
      SELECT fl.aluno_id, fl.disciplina_id, fl.curso_id, fl.e_bolsista,
             nt.turma_id, nt.tempo_id, dd.carga_horaria AS ch,
             random() AS r0, random() AS r1, random() AS r2, random() AS r3, random() AS r4
      FROM (
          SELECT f.aluno_id, f.disciplina_id, f.curso_id, f.e_bolsista, f.tempo_id AS tempo_ant, a.ev
          FROM dm_aluno_prof.fato_aluno_em_disciplina f
          JOIN tmp_al a ON a.aluno_id = f.aluno_id
          WHERE f.nr_tentativa = t AND f.situacao <> 'Aprovado'
      ) fl
      CROSS JOIN LATERAL (
          SELECT tt.turma_id, tt.tempo_id, tt.sem
          FROM tmp_tt tt
          WHERE tt.disciplina_id = fl.disciplina_id AND tt.tempo_id > fl.tempo_ant
          ORDER BY tt.tempo_id LIMIT 1
      ) nt
      JOIN dm_aluno_prof.dim_disciplina dd ON dd.disciplina_id = fl.disciplina_id
      WHERE nt.sem <= COALESCE(fl.ev, 6)
        AND NOT EXISTS (SELECT 1 FROM tmp_tranc tr WHERE tr.aluno_id = fl.aluno_id AND tr.tempo_id = nt.tempo_id)
    )
    INSERT INTO dm_aluno_prof.fato_aluno_em_disciplina (
        tempo_id, turma_id, aluno_id, disciplina_id, curso_id,
        qtd_faltas, ch_adquirida, credito_adquirido, situacao, media_nota, e_bolsista, nr_tentativa)
    SELECT x.tempo_id, x.turma_id, x.aluno_id, x.disciplina_id, x.curso_id, x.faltas,
           CASE WHEN x.faltas <= x.ch * 0.25 AND x.nota >= 5.0 THEN x.ch      ELSE 0 END,
           CASE WHEN x.faltas <= x.ch * 0.25 AND x.nota >= 5.0 THEN x.ch / 15 ELSE 0 END,
           CASE WHEN x.faltas > x.ch * 0.25 THEN 'Reprovado por Falta'
                WHEN x.nota >= 5.0          THEN 'Aprovado'
                ELSE 'Reprovado por Nota' END,
           x.nota, x.e_bolsista, t + 1
    FROM (
        SELECT c.*,
               CASE WHEN c.r4 < 0.10 THEN FLOOR(c.ch * 0.25)::int + 1 + FLOOR(c.r2 * c.ch * 0.15)::int
                    ELSE FLOOR(c.r2 * (c.ch * 0.20 + 1))::int END AS faltas,
               ROUND(LEAST(10, 3.0 + 5.5 * (c.r1 + c.r3) / 2.0 + 1.5 * (1 - c.r2))::numeric, 1) AS nota
        FROM cand c
        WHERE c.r0 < 0.70
    ) x;
  END LOOP;
END $$;

-- C.10 Bolsista = tem auxilio vigente NA DATA DO SEMESTRE (antes era fixo por aluno)
UPDATE dm_aluno_prof.fato_aluno_em_disciplina SET e_bolsista = FALSE;
UPDATE dm_aluno_prof.fato_aluno_em_disciplina f
   SET e_bolsista = TRUE
  FROM dm_aluno_prof.aluno_auxilio x, dm_aluno_prof.dim_data d
 WHERE d.tempo_id = f.tempo_id
   AND x.aluno_id = f.aluno_id
   AND d.data_completa BETWEEN x.data_inicio AND COALESCE(x.data_fim, DATE '9999-12-31');

-- C.11 CH integralizada = soma real das CH aprovadas (inclui repeticoes aprovadas)
UPDATE dm_aluno_prof.dim_aluno SET ch_integralizada = 0;
UPDATE dm_aluno_prof.dim_aluno a
   SET ch_integralizada = s.ch
  FROM (SELECT aluno_id, SUM(ch_adquirida)::int AS ch
          FROM dm_aluno_prof.fato_aluno_em_disciplina GROUP BY aluno_id) s
 WHERE s.aluno_id = a.aluno_id;

-- C.12 Vagas ofertadas por turma (~17% das turmas ficam superlotadas, outras ociosas)
UPDATE dm_aluno_prof.dim_turma_disciplina t
   SET vagas_ofertadas = GREATEST(10, (ROUND(f.n * (0.9 + 0.6 * random()) / 5.0) * 5)::int)
  FROM (SELECT turma_id, COUNT(*) AS n
          FROM dm_aluno_prof.fato_aluno_em_disciplina GROUP BY turma_id) f
 WHERE f.turma_id = t.turma_id;
UPDATE dm_aluno_prof.dim_turma_disciplina SET vagas_ofertadas = 30 WHERE vagas_ofertadas IS NULL;
UPDATE dm_prof.dim_turma_disciplina p SET vagas_ofertadas = a.vagas_ofertadas
  FROM dm_aluno_prof.dim_turma_disciplina a WHERE a.turma_id = p.turma_id;

-- C.13 Situacao de matricula por semestre (Ativo | Trancado | Cancelado).
--      'Formado' existe como valor valido, mas ninguem se forma ate 2026.1
--      (menor curso tem 8 semestres e a primeira coorte e 2023.1).
INSERT INTO dm_aluno_prof.fato_matricula_periodo (tempo_id, aluno_id, curso_id, semestre_curso, situacao)
SELECT (make_date(2023 + s.m / 2, CASE WHEN s.m % 2 = 0 THEN 6 ELSE 12 END, 15) - DATE '2023-01-01') + 1,
       a.aluno_id, a.curso_id, s.m - a.e + 1,
       CASE WHEN tr.aluno_id IS NOT NULL            THEN 'Trancado'
            WHEN a.ev IS NOT NULL AND s.m = a.ev    THEN 'Cancelado'
            ELSE 'Ativo' END
FROM tmp_al a
CROSS JOIN LATERAL generate_series(a.e, COALESCE(a.ev, 6)) AS s(m)
LEFT JOIN tmp_tranc tr ON tr.aluno_id = a.aluno_id AND tr.sem = s.m;

-- C.14 Refaz o fato agregado por turma (a fato de alunos mudou: repeticoes e trancamentos)
TRUNCATE TABLE dm_prof.fato_rend_disciplina;

INSERT INTO dm_prof.fato_rend_disciplina (
    tempo_id, turma_id, turma_disciplina_id, curso_id,
    qtd_aprn, qtd_rprn, qtd_rprf, total_reprovados,
    menor_notas, maior_notas, mediana_notas, media_notas, media_faltas,
    qtd_notas_0_a_2_9, qtd_notas_3_a_6_9, qtd_notas_7_a_10,
    qtd_matriculados, prct_aprovados
)
SELECT
    tempo_id, turma_id, disciplina_id, curso_id,
    COUNT(*) FILTER (WHERE situacao = 'Aprovado'),
    COUNT(*) FILTER (WHERE situacao = 'Reprovado por Nota'),
    COUNT(*) FILTER (WHERE situacao = 'Reprovado por Falta'),
    COUNT(*) FILTER (WHERE situacao <> 'Aprovado'),
    MIN(media_nota), MAX(media_nota),
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY media_nota)::numeric, 2),
    ROUND(AVG(media_nota)::numeric, 2),
    ROUND(AVG(qtd_faltas)::numeric, 2),
    COUNT(*) FILTER (WHERE media_nota < 3.0),
    COUNT(*) FILTER (WHERE media_nota >= 3.0 AND media_nota < 7.0),
    COUNT(*) FILTER (WHERE media_nota >= 7.0),
    COUNT(*),
    ROUND((COUNT(*) FILTER (WHERE situacao = 'Aprovado')::numeric / COUNT(*)::numeric) * 100, 2)
FROM dm_aluno_prof.fato_aluno_em_disciplina
GROUP BY tempo_id, turma_id, disciplina_id, curso_id;

-- C.15 Avaliacao docente (nota 1-5, levemente correlacionada com o rendimento da turma)
INSERT INTO dm_prof.avaliacao_docente (turma_id, professor_id, tempo_id, nota_media, qtd_respondentes)
SELECT f.turma_id, p.professor_id, f.tempo_id,
       ROUND(LEAST(5, GREATEST(1, 3.6 + 0.25 * (f.media_notas - 7.0) + (random() - 0.5) * 1.4))::numeric, 2),
       GREATEST(1, ROUND(f.qtd_matriculados * (0.3 + 0.4 * random()))::int)
FROM dm_prof.fato_rend_disciplina f
JOIN dm_prof.dim_turma_disciplina t ON t.turma_id = f.turma_id
CROSS JOIN LATERAL (VALUES (t.sk_p1), (t.sk_p2), (t.sk_p3)) AS p(professor_id)
WHERE p.professor_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- D. CONFERENCIAS
-- ----------------------------------------------------------------------------
SELECT 'fato_aluno_em_disciplina' AS tabela, COUNT(*) AS linhas FROM dm_aluno_prof.fato_aluno_em_disciplina
UNION ALL SELECT '  com nr_tentativa > 1',  COUNT(*) FROM dm_aluno_prof.fato_aluno_em_disciplina WHERE nr_tentativa > 1
UNION ALL SELECT 'fato_matricula_periodo', COUNT(*) FROM dm_aluno_prof.fato_matricula_periodo
UNION ALL SELECT '  Trancado',              COUNT(*) FROM dm_aluno_prof.fato_matricula_periodo WHERE situacao = 'Trancado'
UNION ALL SELECT '  Cancelado',             COUNT(*) FROM dm_aluno_prof.fato_matricula_periodo WHERE situacao = 'Cancelado'
UNION ALL SELECT 'aluno_auxilio',           COUNT(*) FROM dm_aluno_prof.aluno_auxilio
UNION ALL SELECT 'aluno_atividade_extra',   COUNT(*) FROM dm_aluno_prof.aluno_atividade_extra
UNION ALL SELECT 'disciplina_prerequisito', COUNT(*) FROM dm_aluno_prof.disciplina_prerequisito
UNION ALL SELECT 'fato_rend_disciplina',    COUNT(*) FROM dm_prof.fato_rend_disciplina
UNION ALL SELECT 'avaliacao_docente',       COUNT(*) FROM dm_prof.avaliacao_docente;

-- Aluno matriculado em disciplina num semestre trancado ou cancelado antes (deve ser 0)
SELECT COUNT(*) AS erros_matricula_em_semestre_trancado
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN dm_aluno_prof.fato_matricula_periodo m ON m.aluno_id = f.aluno_id AND m.tempo_id = f.tempo_id
WHERE m.situacao = 'Trancado';
