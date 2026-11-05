-- ============================================================================
-- CONSULTAS ANALITICAS (PDF "DW Alunos e Profs - Consultas Analiticas")
-- Schemas: dm_aluno_prof [F1] e dm_prof [F2]
--
-- Pre-requisito: povoamento_dm_ufpe_corrigido.txt e metadados_extensao_dm.txt
-- ja executados. Cada consulta e independente; rode uma de cada vez.
--
-- NOTAS DE LEITURA
--  * F2: o PDF cita qtd_agm/qtd_rpm/qtd_rpf. No DDL as colunas sao
--    qtd_aprn (aprovados), qtd_rprn (reprovados por nota) e qtd_rprf
--    (reprovados por falta); e o que as consultas usam.
--  * Semestre de referencia dos dados: 2023.1 a 2026.1 (7 semestres).
--  * O PDF nao tem as consultas 1.8, 2.11 e 4.4; a numeracao segue o PDF.
--  * Consultas que dependem de dados que nao existem no volume gerado
--    (ninguem se forma ate 2026.1, nao ha disciplinas atendendo outros
--    cursos) estao escritas corretamente, mas retornam vazio. Cada uma
--    traz um aviso.
-- ============================================================================


-- ############################################################################
-- 0. VIEWS DE APOIO (rode uma vez)
-- ############################################################################

-- F2 + dimensoes (grao: turma)
CREATE OR REPLACE VIEW dm_prof.vw_rend_turma AS
SELECT f.tempo_id,
       dt.ano, dt.semestre, dt.ano || '.' || dt.semestre AS ano_semestre,
       f.turma_id, t.codigo_turma, t.sk_p1, t.sk_p2, t.sk_p3, t.vagas_ofertadas,
       d.disciplina_id, d.codigo_disciplina, d.nome AS disciplina, d.periodo, d.tipo AS tipo_disciplina,
       c.curso_id, c.nome AS curso, c.departamento, c.centro, c.campi, c.conceito_enade,
       f.qtd_aprn, f.qtd_rprn, f.qtd_rprf, f.total_reprovados,
       f.menor_notas, f.maior_notas, f.mediana_notas, f.media_notas, f.media_faltas,
       f.qtd_notas_0_a_2_9, f.qtd_notas_3_a_6_9, f.qtd_notas_7_a_10,
       f.qtd_matriculados, f.prct_aprovados
FROM dm_prof.fato_rend_disciplina f
JOIN dm_prof.dim_data dt              ON dt.tempo_id = f.tempo_id
JOIN dm_prof.dim_turma_disciplina t   ON t.turma_id = f.turma_id
JOIN dm_prof.dim_disciplina d         ON d.disciplina_id = f.turma_disciplina_id
JOIN dm_prof.dim_curso c              ON c.curso_id = f.curso_id;

-- F1 + dimensoes (grao: aluno x turma). sem_abs = ano*2 + semestre (indice absoluto do semestre)
CREATE OR REPLACE VIEW dm_aluno_prof.vw_aluno_disciplina AS
SELECT f.tempo_id, f.turma_id, f.aluno_id, f.disciplina_id, f.curso_id,
       f.qtd_faltas, f.ch_adquirida, f.credito_adquirido, f.situacao, f.media_nota,
       f.e_bolsista, f.nr_tentativa,
       dt.data_completa, dt.ano, dt.semestre, dt.ano_semestre, dt.ano * 2 + dt.semestre AS sem_abs,
       d.codigo_disciplina, d.nome AS disciplina, d.periodo AS periodo_sugerido,
       d.carga_horaria, d.creditos, d.tipo AS tipo_disciplina,
       c.nome AS curso, c.departamento, c.centro, c.campi, c.curriculo,
       a.faixa_etaria, a.genero, a.raca_etnia, a.faixa_economica, a.tipo_cota,
       a.tipo_escola_em, a.assistencia_estudantil,
       a.ano_ingresso, a.semestre_ingresso, a.ano_semestre_ingresso,
       a.ano_ingresso * 2 + a.semestre_ingresso AS ingresso_abs,
       a.tipo_evasao, a.ano_evasao, a.semestre_evasao,
       CASE WHEN a.ano_evasao IS NULL THEN NULL ELSE a.ano_evasao * 2 + a.semestre_evasao END AS evasao_abs,
       (a.tipo_cota <> 'Ampla Concorrência') AS cotista
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN dm_aluno_prof.dim_data dt        ON dt.tempo_id = f.tempo_id
JOIN dm_aluno_prof.dim_disciplina d   ON d.disciplina_id = f.disciplina_id
JOIN dm_aluno_prof.dim_curso c        ON c.curso_id = f.curso_id
JOIN dm_aluno_prof.dim_aluno a        ON a.aluno_id = f.aluno_id;

-- Ultimo semestre concluido na base (usado como "hoje" em varias consultas)
CREATE OR REPLACE VIEW dm_aluno_prof.vw_semestre_ref AS
SELECT MAX(dt.ano * 2 + dt.semestre) AS sem_abs_ref
FROM dm_aluno_prof.fato_matricula_periodo m
JOIN dm_aluno_prof.dim_data dt ON dt.tempo_id = m.tempo_id;


-- ############################################################################
-- 1. REPROVACAO POR NOTA E POR FALTA
-- ############################################################################

-- 1.1 Taxa de reprovacao por disciplina por semestre (nota x falta) [F2]
SELECT codigo_disciplina, disciplina, curso, ano_semestre,
       SUM(qtd_matriculados) AS matriculados,
       ROUND(100.0 * SUM(qtd_rprn) / SUM(qtd_matriculados), 2) AS pct_reprov_nota,
       ROUND(100.0 * SUM(qtd_rprf) / SUM(qtd_matriculados), 2) AS pct_reprov_falta,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprov_total
FROM dm_prof.vw_rend_turma
GROUP BY codigo_disciplina, disciplina, curso, ano_semestre
ORDER BY ano_semestre, pct_reprov_total DESC;

-- 1.2a Top 10 disciplinas "gargalo" POR CURSO [F2]
SELECT * FROM (
    SELECT curso, codigo_disciplina, disciplina,
           SUM(qtd_matriculados) AS matriculados,
           ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprovacao,
           ROW_NUMBER() OVER (PARTITION BY curso
                              ORDER BY SUM(total_reprovados)::numeric / SUM(qtd_matriculados) DESC) AS ranking
    FROM dm_prof.vw_rend_turma
    GROUP BY curso, codigo_disciplina, disciplina
    HAVING SUM(qtd_matriculados) >= 30
) r
WHERE ranking <= 10
ORDER BY curso, ranking;

-- 1.2b Top 10 POR DEPARTAMENTO (agrupa pelo nome da disciplina) [F2]
SELECT * FROM (
    SELECT departamento, disciplina,
           SUM(qtd_matriculados) AS matriculados,
           ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprovacao,
           ROW_NUMBER() OVER (PARTITION BY departamento
                              ORDER BY SUM(total_reprovados)::numeric / SUM(qtd_matriculados) DESC) AS ranking
    FROM dm_prof.vw_rend_turma
    GROUP BY departamento, disciplina
    HAVING SUM(qtd_matriculados) >= 30
) r
WHERE ranking <= 10
ORDER BY departamento, ranking;

-- 1.2c Top 10 POR CENTRO [F2]
SELECT * FROM (
    SELECT centro, disciplina,
           SUM(qtd_matriculados) AS matriculados,
           ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprovacao,
           ROW_NUMBER() OVER (PARTITION BY centro
                              ORDER BY SUM(total_reprovados)::numeric / SUM(qtd_matriculados) DESC) AS ranking
    FROM dm_prof.vw_rend_turma
    GROUP BY centro, disciplina
    HAVING SUM(qtd_matriculados) >= 30
) r
WHERE ranking <= 10
ORDER BY centro, ranking;

-- 1.3 Razao reprovacao por falta / reprovacao total por disciplina [F2]
--     Razao alta (>= 0,5) sugere problema de engajamento/frequencia, nao de aprendizagem
SELECT curso, codigo_disciplina, disciplina,
       SUM(total_reprovados) AS reprovados,
       SUM(qtd_rprf)         AS reprovados_falta,
       ROUND(SUM(qtd_rprf)::numeric / NULLIF(SUM(total_reprovados), 0), 3) AS razao_falta_total,
       CASE WHEN SUM(qtd_rprf)::numeric / NULLIF(SUM(total_reprovados), 0) >= 0.5
            THEN 'Engajamento/frequencia' ELSE 'Aprendizagem' END AS leitura
FROM dm_prof.vw_rend_turma
GROUP BY curso, codigo_disciplina, disciplina
HAVING SUM(total_reprovados) > 0
ORDER BY razao_falta_total DESC;

-- 1.4 Distribuicao de notas por faixa e classificacao da turma [F2]
--     Polarizada = menos de 40% das notas na faixa intermediaria (3 a 6,9)
SELECT curso, codigo_disciplina, disciplina,
       SUM(qtd_notas_0_a_2_9) AS faixa_0_a_2_9,
       SUM(qtd_notas_3_a_6_9) AS faixa_3_a_6_9,
       SUM(qtd_notas_7_a_10)  AS faixa_7_a_10,
       ROUND(100.0 * SUM(qtd_notas_0_a_2_9) / SUM(qtd_matriculados), 1) AS pct_0_a_2_9,
       ROUND(100.0 * SUM(qtd_notas_3_a_6_9) / SUM(qtd_matriculados), 1) AS pct_3_a_6_9,
       ROUND(100.0 * SUM(qtd_notas_7_a_10)  / SUM(qtd_matriculados), 1) AS pct_7_a_10,
       CASE WHEN 100.0 * SUM(qtd_notas_3_a_6_9) / SUM(qtd_matriculados) < 40
            THEN 'Polarizada' ELSE 'Concentrada' END AS distribuicao
FROM dm_prof.vw_rend_turma
GROUP BY curso, codigo_disciplina, disciplina
ORDER BY pct_0_a_2_9 DESC;

-- 1.5 Diferenca media x mediana por turma (assimetria) [F2]
SELECT ano_semestre, curso, codigo_disciplina, codigo_turma,
       qtd_matriculados, media_notas, mediana_notas,
       ROUND(media_notas - mediana_notas, 2)      AS media_menos_mediana,
       ROUND(ABS(media_notas - mediana_notas), 2) AS distancia
FROM dm_prof.vw_rend_turma
WHERE qtd_matriculados >= 10
ORDER BY distancia DESC
LIMIT 50;

-- 1.6a Variancia do % de aprovacao entre turmas da mesma disciplina [F2 + Professor]
SELECT codigo_disciplina, disciplina, curso,
       COUNT(*)                                        AS turmas,
       COUNT(DISTINCT sk_p1)                           AS professores,
       ROUND(AVG(prct_aprovados), 2)                   AS media_pct_aprovacao,
       ROUND(VAR_POP(prct_aprovados), 2)               AS variancia_pct_aprovacao,
       ROUND(STDDEV_POP(prct_aprovados), 2)            AS desvio_pct_aprovacao
FROM dm_prof.vw_rend_turma
GROUP BY codigo_disciplina, disciplina, curso
HAVING COUNT(*) >= 2
ORDER BY variancia_pct_aprovacao DESC;

-- 1.6b Professor x media da disciplina (detalhe por professor principal) [F2 + Professor]
SELECT r.codigo_disciplina, r.disciplina, p.nome AS professor,
       COUNT(*) AS turmas,
       ROUND(AVG(r.prct_aprovados), 2) AS aprovacao_prof,
       ROUND(AVG(AVG(r.prct_aprovados)) OVER (PARTITION BY r.codigo_disciplina), 2) AS media_aprovacao_disciplina,
       ROUND(AVG(r.prct_aprovados) - AVG(AVG(r.prct_aprovados)) OVER (PARTITION BY r.codigo_disciplina), 2) AS diferenca_vs_disciplina
FROM dm_prof.vw_rend_turma r
JOIN dm_prof.dim_professor p ON p.professor_id = r.sk_p1
GROUP BY r.codigo_disciplina, r.disciplina, p.professor_id, p.nome
ORDER BY ABS(AVG(r.prct_aprovados) - AVG(AVG(r.prct_aprovados)) OVER (PARTITION BY r.codigo_disciplina)) DESC
LIMIT 50;

-- 1.7 Reprovacao por periodo do curriculo (1o ao 10o) [F2 + Disciplina]
SELECT periodo,
       SUM(qtd_matriculados) AS matriculados,
       ROUND(100.0 * SUM(qtd_rprn) / SUM(qtd_matriculados), 2) AS pct_reprov_nota,
       ROUND(100.0 * SUM(qtd_rprf) / SUM(qtd_matriculados), 2) AS pct_reprov_falta,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprov_total
FROM dm_prof.vw_rend_turma
GROUP BY periodo
ORDER BY periodo;

-- 1.7b Mesmo recorte, por curso
SELECT curso, periodo,
       SUM(qtd_matriculados) AS matriculados,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprov_total
FROM dm_prof.vw_rend_turma
GROUP BY curso, periodo
ORDER BY curso, periodo;

-- 1.9 Reprovacao por semestre do ano (1o x 2o) e por semestre letivo [F2 + Data]
--     A coluna desvio_vs_media_geral destaca semestres atipicos (greve, calendario)
SELECT ano_semestre, semestre,
       SUM(qtd_matriculados) AS matriculados,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprov_total,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados)
             - 100.0 * SUM(SUM(total_reprovados)) OVER () / SUM(SUM(qtd_matriculados)) OVER (), 2) AS desvio_vs_media_geral
FROM dm_prof.vw_rend_turma
GROUP BY ano_semestre, semestre
ORDER BY ano_semestre;

SELECT semestre AS semestre_do_ano,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprov_total
FROM dm_prof.vw_rend_turma
GROUP BY semestre
ORDER BY semestre;

-- 1.10 Perfil de reprovacao por perfil do aluno [F1 + Aluno]
SELECT p.dimensao, p.valor,
       COUNT(*) AS matriculas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.situacao <> 'Aprovado') / COUNT(*), 2) AS pct_reprovacao,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.situacao = 'Reprovado por Nota')  / COUNT(*), 2) AS pct_reprov_nota,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.situacao = 'Reprovado por Falta') / COUNT(*), 2) AS pct_reprov_falta
FROM dm_aluno_prof.vw_aluno_disciplina f
CROSS JOIN LATERAL (VALUES
    ('faixa_etaria',    f.faixa_etaria),
    ('genero',          f.genero),
    ('raca_etnia',      f.raca_etnia),
    ('faixa_economica', f.faixa_economica),
    ('cotista',         CASE WHEN f.cotista THEN 'Sim' ELSE 'Não' END),
    ('tipo_cota',       f.tipo_cota),
    ('escola_origem',   f.tipo_escola_em),
    ('bolsista',        CASE WHEN f.e_bolsista THEN 'Sim' ELSE 'Não' END)
) AS p(dimensao, valor)
GROUP BY p.dimensao, p.valor
ORDER BY p.dimensao, pct_reprovacao DESC;

-- 1.11a Correlacao entre faltas e nota por disciplina [F1]
SELECT curso, codigo_disciplina, disciplina,
       COUNT(*) AS matriculas,
       ROUND(CORR(qtd_faltas, media_nota)::numeric, 3) AS correlacao_faltas_nota
FROM dm_aluno_prof.vw_aluno_disciplina
GROUP BY curso, codigo_disciplina, disciplina
HAVING COUNT(*) >= 30
ORDER BY correlacao_faltas_nota;

-- 1.11b Ponto de corte: aprovacao por faixa de % de faltas sobre a carga horaria [F1]
--       (a queda abrupta aparece ao passar de 25%)
SELECT (FLOOR(100.0 * qtd_faltas / carga_horaria / 5) * 5)::int AS faixa_pct_faltas_inicio,
       COUNT(*) AS matriculas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE situacao = 'Aprovado') / COUNT(*), 2) AS pct_aprovacao
FROM dm_aluno_prof.vw_aluno_disciplina
GROUP BY 1
ORDER BY 1;

-- 1.12 Reprovacao reincidente: reprovados 2+ vezes na mesma disciplina [F1 + nr_tentativa]
SELECT a.numero_matricula, a.nome AS aluno, v.curso, v.codigo_disciplina, v.disciplina,
       COUNT(*) FILTER (WHERE v.situacao <> 'Aprovado') AS reprovacoes,
       MAX(v.nr_tentativa) AS tentativas
FROM dm_aluno_prof.vw_aluno_disciplina v
JOIN dm_aluno_prof.dim_aluno a ON a.aluno_id = v.aluno_id
GROUP BY a.aluno_id, a.numero_matricula, a.nome, v.curso, v.codigo_disciplina, v.disciplina
HAVING COUNT(*) FILTER (WHERE v.situacao <> 'Aprovado') >= 2
ORDER BY reprovacoes DESC, v.curso;

-- 1.12b Disciplinas com mais reincidentes
SELECT curso, codigo_disciplina, disciplina, COUNT(*) AS alunos_reincidentes
FROM (
    SELECT v.aluno_id, v.curso, v.codigo_disciplina, v.disciplina
    FROM dm_aluno_prof.vw_aluno_disciplina v
    GROUP BY v.aluno_id, v.curso, v.codigo_disciplina, v.disciplina
    HAVING COUNT(*) FILTER (WHERE v.situacao <> 'Aprovado') >= 2
) r
GROUP BY curso, codigo_disciplina, disciplina
ORDER BY alunos_reincidentes DESC;

-- 1.13 Efeito domino: quem reprovou no pre-requisito X, como vai na disciplina Y [F1 + pre-requisitos]
--      Compara, na 1a tentativa de Y, reprovacao e evasao de quem reprovou x quem passou em X
WITH x_res AS (
    SELECT aluno_id, disciplina_id AS x_id,
           BOOL_OR(situacao <> 'Aprovado') AS reprovou_x,
           MIN(tempo_id) AS tempo_x
    FROM dm_aluno_prof.fato_aluno_em_disciplina
    WHERE nr_tentativa = 1
    GROUP BY aluno_id, disciplina_id
)
SELECT dx.codigo_disciplina AS prerequisito, dx.nome AS nome_prerequisito,
       dy.codigo_disciplina AS disciplina_seguinte, dy.nome AS nome_seguinte,
       xr.reprovou_x,
       COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE fy.situacao <> 'Aprovado') / COUNT(*), 2) AS pct_reprov_em_y,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2)   AS pct_evasao
FROM dm_aluno_prof.disciplina_prerequisito pr
JOIN dm_aluno_prof.dim_disciplina dx ON dx.disciplina_id = pr.prerequisito_id
JOIN dm_aluno_prof.dim_disciplina dy ON dy.disciplina_id = pr.disciplina_id
JOIN x_res xr ON xr.x_id = pr.prerequisito_id
JOIN dm_aluno_prof.fato_aluno_em_disciplina fy
  ON fy.aluno_id = xr.aluno_id AND fy.disciplina_id = pr.disciplina_id
 AND fy.nr_tentativa = 1 AND fy.tempo_id > xr.tempo_x
JOIN dm_aluno_prof.dim_aluno a ON a.aluno_id = xr.aluno_id
GROUP BY dx.codigo_disciplina, dx.nome, dy.codigo_disciplina, dy.nome, xr.reprovou_x
HAVING COUNT(*) >= 20
ORDER BY dx.codigo_disciplina, dy.codigo_disciplina, xr.reprovou_x DESC;


-- ############################################################################
-- 2. EVASAO   (coorte = ano_semestre_ingresso)
-- ############################################################################

-- 2.1 Taxa de evasao por curso e coorte [Aluno]
SELECT c.nome AS curso, a.ano_semestre_ingresso AS coorte,
       COUNT(*) AS ingressantes,
       COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') AS evadidos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
GROUP BY c.nome, a.ano_semestre_ingresso
ORDER BY c.nome, a.ano_semestre_ingresso;

-- 2.2 Evasao por tipo x curso x ano [Aluno]
SELECT c.nome AS curso, a.ano_evasao, a.tipo_evasao, COUNT(*) AS alunos
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
WHERE a.tipo_evasao <> 'Ativo'
GROUP BY c.nome, a.ano_evasao, a.tipo_evasao
ORDER BY c.nome, a.ano_evasao, a.tipo_evasao;

-- 2.3 Curva de sobrevivencia por coorte: % ainda ativo k semestres apos o ingresso [Aluno + Data]
--     So mostra k ja observavel (ate o ultimo semestre concluido da base)
WITH al AS (
    SELECT a.aluno_id, a.ano_semestre_ingresso AS coorte,
           a.ano_ingresso * 2 + a.semestre_ingresso AS ing,
           CASE WHEN a.ano_evasao IS NULL THEN NULL ELSE a.ano_evasao * 2 + a.semestre_evasao END AS evas
    FROM dm_aluno_prof.dim_aluno a
), ref AS (SELECT sem_abs_ref FROM dm_aluno_prof.vw_semestre_ref)
SELECT al.coorte, k.k AS semestres_apos_ingresso,
       COUNT(*) AS alunos_coorte,
       COUNT(*) FILTER (WHERE al.evas IS NULL OR al.evas > al.ing + k.k) AS ainda_ativos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE al.evas IS NULL OR al.evas > al.ing + k.k) / COUNT(*), 2) AS pct_sobrevivencia
FROM al
CROSS JOIN ref
CROSS JOIN generate_series(0, 6) AS k(k)
WHERE al.ing + k.k <= ref.sem_abs_ref
GROUP BY al.coorte, k.k
ORDER BY al.coorte, k.k;

-- 2.4 Semestre critico de evasao (semestre do curso em que evade) [Aluno]
SELECT c.nome AS curso,
       (a.ano_evasao * 2 + a.semestre_evasao) - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 AS semestre_do_curso,
       COUNT(*) AS evadidos
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
WHERE a.tipo_evasao <> 'Ativo'
GROUP BY c.nome, 2
ORDER BY c.nome, evadidos DESC;

SELECT (a.ano_evasao * 2 + a.semestre_evasao) - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 AS semestre_do_curso,
       COUNT(*) AS evadidos
FROM dm_aluno_prof.dim_aluno a
WHERE a.tipo_evasao <> 'Ativo'
GROUP BY 1 ORDER BY evadidos DESC;

-- 2.5 Evasao por forma/meio de ingresso, cota e escola do ensino medio [Aluno]
SELECT p.dimensao, p.valor, COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
FROM dm_aluno_prof.dim_aluno a
CROSS JOIN LATERAL (VALUES
    ('forma_ingresso', a.forma_ingresso),
    ('meio_ingresso',  a.meio_ingresso),
    ('tipo_cota',      a.tipo_cota),
    ('tipo_escola_em', a.tipo_escola_em)
) AS p(dimensao, valor)
GROUP BY p.dimensao, p.valor
ORDER BY p.dimensao, taxa_evasao DESC;

-- 2.6 Evasao por faixa economica, assistencia e bolsista: a assistencia reduz a evasao? [Aluno + F1]
SELECT a.faixa_economica, a.assistencia_estudantil,
       (b.aluno_id IS NOT NULL) AS foi_bolsista,
       COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
FROM dm_aluno_prof.dim_aluno a
LEFT JOIN (SELECT DISTINCT aluno_id FROM dm_aluno_prof.fato_aluno_em_disciplina WHERE e_bolsista) b
       ON b.aluno_id = a.aluno_id
GROUP BY a.faixa_economica, a.assistencia_estudantil, (b.aluno_id IS NOT NULL)
ORDER BY a.faixa_economica, a.assistencia_estudantil;

-- 2.7 Evasao por bairro de residencia (+ distancia media ao campus) [Aluno]
SELECT c.campi, a.bairro_residencia,
       COUNT(*) AS alunos,
       ROUND(AVG(a.distancia_campus_km), 1)    AS dist_media_km,
       ROUND(AVG(a.tempo_deslocamento_min), 0) AS deslocamento_medio_min,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
GROUP BY c.campi, a.bairro_residencia
ORDER BY taxa_evasao DESC;

-- 2.8 Evasao por tempo entre conclusao do EM e ingresso [Aluno]
SELECT CASE WHEN a.ano_ingresso - a.ano_conclusao_em <= 1 THEN '0-1 ano'
            WHEN a.ano_ingresso - a.ano_conclusao_em <= 3 THEN '2-3 anos'
            WHEN a.ano_ingresso - a.ano_conclusao_em <= 6 THEN '4-6 anos'
            ELSE '7+ anos' END AS intervalo_em_ingresso,
       COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
FROM dm_aluno_prof.dim_aluno a
GROUP BY 1
ORDER BY 1;

-- 2.9 Indicadores precoces de evasao: ativos com 2+ semestres de baixo rendimento,
--     muitas faltas ou CH integralizada abaixo do esperado [F1 + Aluno]
--     Esperado = CH das disciplinas obrigatorias dos periodos ja transcorridos
WITH ref AS (SELECT sem_abs_ref FROM dm_aluno_prof.vw_semestre_ref),
sem_aluno AS (
    SELECT aluno_id, sem_abs,
           100.0 * COUNT(*) FILTER (WHERE situacao = 'Aprovado') / COUNT(*) AS pct_aprov_sem,
           AVG(qtd_faltas::numeric / carga_horaria) AS faltas_rel
    FROM dm_aluno_prof.vw_aluno_disciplina
    GROUP BY aluno_id, sem_abs
),
risco AS (
    SELECT aluno_id,
           COUNT(*) FILTER (WHERE pct_aprov_sem < 50) AS semestres_baixo_rend,
           ROUND(AVG(faltas_rel) * 100, 1)            AS media_pct_faltas
    FROM sem_aluno GROUP BY aluno_id
)
SELECT a.numero_matricula, a.nome, c.nome AS curso, a.ano_semestre_ingresso AS coorte,
       r.semestres_baixo_rend, r.media_pct_faltas,
       a.ch_integralizada,
       esp.ch_esperada,
       ROUND(100.0 * a.ch_integralizada / NULLIF(esp.ch_esperada, 0), 1) AS pct_do_esperado
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
JOIN risco r ON r.aluno_id = a.aluno_id
CROSS JOIN ref
CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(d.carga_horaria), 0) AS ch_esperada
    FROM dm_aluno_prof.dim_disciplina d
    WHERE d.fk_curso = a.curso_id AND d.tipo = 'Obrigatória'
      AND d.periodo <= ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1
) esp
WHERE a.tipo_evasao = 'Ativo'
  AND (r.semestres_baixo_rend >= 2
       OR r.media_pct_faltas >= 15
       OR a.ch_integralizada < 0.7 * esp.ch_esperada)
ORDER BY r.semestres_baixo_rend DESC, pct_do_esperado;

-- 2.10 Evasao por disciplina: disciplinas cursadas no ULTIMO semestre antes de evadir,
--      com reprovacao por falta (infrequencia) [F1]
--      Parte "trancado" (com disciplina) nao e possivel: o trancamento e por semestre, ver 2.10b
SELECT curso, codigo_disciplina, disciplina,
       COUNT(*) AS evadidos_que_cursaram,
       COUNT(*) FILTER (WHERE situacao = 'Reprovado por Falta') AS infrequentes,
       ROUND(100.0 * COUNT(*) FILTER (WHERE situacao = 'Reprovado por Falta') / COUNT(*), 1) AS pct_infrequentes
FROM dm_aluno_prof.vw_aluno_disciplina
WHERE evasao_abs IS NOT NULL AND sem_abs = evasao_abs
GROUP BY curso, codigo_disciplina, disciplina
HAVING COUNT(*) >= 5
ORDER BY infrequentes DESC;

-- 2.10b Trancamento imediatamente antes da evasao, por curso [fato_matricula_periodo]
SELECT c.nome AS curso,
       COUNT(*) AS cancelamentos,
       COUNT(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM dm_aluno_prof.fato_matricula_periodo t
           WHERE t.aluno_id = m.aluno_id AND t.situacao = 'Trancado'
             AND t.semestre_curso = m.semestre_curso - 1)) AS trancou_no_semestre_anterior
FROM dm_aluno_prof.fato_matricula_periodo m
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = m.curso_id
WHERE m.situacao = 'Cancelado'
GROUP BY c.nome
ORDER BY cancelamentos DESC;

-- 2.12 Retencao x evasao: ativos fora do ciclo minimo e ainda dentro do maximo (risco de jubilamento) [Aluno]
--      AVISO: retorna vazio neste volume (so ha 7 semestres de historico; o menor ciclo minimo e 8)
WITH ref AS (SELECT sem_abs_ref FROM dm_aluno_prof.vw_semestre_ref)
SELECT a.numero_matricula, a.nome, c.nome AS curso, a.ano_semestre_ingresso AS coorte,
       ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 AS semestres_cursados,
       a.qtd_min_conc, a.qtd_max_conc,
       a.qtd_max_conc - (ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1) AS semestres_ate_jubilamento
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
CROSS JOIN ref
WHERE a.tipo_evasao = 'Ativo'
  AND ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 > a.qtd_min_conc
  AND ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 <= a.qtd_max_conc
ORDER BY semestres_ate_jubilamento;

-- 2.13 Alunos "blocados" (flg_blocado): perfil e tempo ate evadir [Aluno]
--      O PDF cita flg_bloqueado; o DDL tem flg_blocado (aqui usado como esta).
--      Se a ideia for "bloqueio de matricula" com duracao, falta um historico de bloqueios.
SELECT a.flg_blocado, c.nome AS curso, a.genero, a.faixa_economica,
       COUNT(*) AS alunos,
       COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') AS evadidos,
       ROUND(AVG((a.ano_evasao * 2 + a.semestre_evasao) - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1)
             FILTER (WHERE a.tipo_evasao <> 'Ativo'), 2) AS semestres_medios_ate_evadir
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
GROUP BY a.flg_blocado, c.nome, a.genero, a.faixa_economica
ORDER BY a.flg_blocado DESC, alunos DESC;


-- ############################################################################
-- 3. PROGRESSAO E INTEGRALIZACAO
-- ############################################################################

-- 3.1 % de ch_integralizada sobre a CH do curso, por coorte [Aluno + Curso]
--     (as disciplinas modeladas somam ~1.100h por curso, entao o % absoluto e baixo;
--      use a comparacao entre coortes/cursos)
SELECT c.nome AS curso, a.ano_semestre_ingresso AS coorte,
       COUNT(*) AS alunos,
       ROUND(AVG(a.ch_integralizada), 0) AS ch_media_integralizada,
       c.carga_horaria AS ch_curso,
       ROUND(100.0 * AVG(a.ch_integralizada) / c.carga_horaria, 2) AS pct_integralizado
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
WHERE a.tipo_evasao = 'Ativo'
GROUP BY c.nome, c.carga_horaria, a.ano_semestre_ingresso
ORDER BY c.nome, a.ano_semestre_ingresso;

-- 3.2 Alunos dentro do prazo minimo, fora do minimo e em risco do maximo, por curso [Aluno]
WITH ref AS (SELECT sem_abs_ref FROM dm_aluno_prof.vw_semestre_ref),
st AS (
    SELECT a.curso_id,
           ref.sem_abs_ref - (a.ano_ingresso * 2 + a.semestre_ingresso) + 1 AS cursados,
           a.qtd_min_conc, a.qtd_max_conc
    FROM dm_aluno_prof.dim_aluno a CROSS JOIN ref
    WHERE a.tipo_evasao = 'Ativo'
)
SELECT c.nome AS curso,
       COUNT(*) FILTER (WHERE st.cursados <= st.qtd_min_conc)                              AS dentro_prazo_minimo,
       COUNT(*) FILTER (WHERE st.cursados > st.qtd_min_conc AND st.cursados < st.qtd_max_conc - 1) AS fora_prazo_minimo,
       COUNT(*) FILTER (WHERE st.cursados >= st.qtd_max_conc - 1)                          AS risco_prazo_maximo
FROM st JOIN dm_aluno_prof.dim_curso c ON c.curso_id = st.curso_id
GROUP BY c.nome
ORDER BY c.nome;

-- 3.3 Tempo medio de conclusao vs minimo e maximo [fato_matricula_periodo]
--     AVISO: vazio neste volume (ninguem consta como 'Formado' ate 2026.1)
SELECT c.nome AS curso,
       COUNT(*) AS formados,
       ROUND(AVG(m.semestre_curso), 2) AS tempo_medio_semestres,
       c.tempo_min_conclusao, c.tempo_max_conclusao
FROM dm_aluno_prof.fato_matricula_periodo m
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = m.curso_id
WHERE m.situacao = 'Formado'
GROUP BY c.nome, c.tempo_min_conclusao, c.tempo_max_conclusao
ORDER BY c.nome;

-- 3.4 Taxa de sucesso por coorte: formados no prazo, com atraso, evadidos, ainda ativos [Aluno + situacao]
WITH ult AS (
    SELECT DISTINCT ON (m.aluno_id) m.aluno_id, m.situacao, m.semestre_curso
    FROM dm_aluno_prof.fato_matricula_periodo m
    ORDER BY m.aluno_id, m.tempo_id DESC
)
SELECT a.ano_semestre_ingresso AS coorte,
       COUNT(*) AS ingressantes,
       COUNT(*) FILTER (WHERE u.situacao = 'Formado' AND u.semestre_curso <= c.tempo_min_conclusao) AS formados_no_prazo,
       COUNT(*) FILTER (WHERE u.situacao = 'Formado' AND u.semestre_curso >  c.tempo_min_conclusao) AS formados_com_atraso,
       COUNT(*) FILTER (WHERE u.situacao = 'Cancelado') AS evadidos,
       COUNT(*) FILTER (WHERE u.situacao IN ('Ativo', 'Trancado')) AS ainda_ativos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE u.situacao = 'Formado') / COUNT(*), 2) AS taxa_sucesso
FROM dm_aluno_prof.dim_aluno a
JOIN ult u ON u.aluno_id = a.aluno_id
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
GROUP BY a.ano_semestre_ingresso
ORDER BY a.ano_semestre_ingresso;

-- 3.5 Media de creditos adquiridos por semestre por aluno e curso [F1]
--     (tambem mostra creditos cursados, para detectar quem "dilui" a carga)
WITH por_sem AS (
    SELECT aluno_id, curso, sem_abs,
           SUM(creditos)           AS cred_cursados,
           SUM(credito_adquirido)  AS cred_adquiridos
    FROM dm_aluno_prof.vw_aluno_disciplina
    GROUP BY aluno_id, curso, sem_abs
)
SELECT curso,
       COUNT(DISTINCT aluno_id) AS alunos,
       ROUND(AVG(cred_cursados), 2)    AS media_creditos_cursados_sem,
       ROUND(AVG(cred_adquiridos), 2)  AS media_creditos_adquiridos_sem,
       ROUND(100.0 * SUM(cred_adquiridos) / SUM(cred_cursados), 1) AS pct_aproveitamento
FROM por_sem
GROUP BY curso
ORDER BY media_creditos_adquiridos_sem;


-- ############################################################################
-- 4. EQUIDADE E PERFIL DISCENTE
-- ############################################################################

-- 4.1 Perfil dos ingressantes por curso e sua evolucao no tempo [Aluno]
SELECT c.nome AS curso, a.ano_ingresso, p.dimensao, p.valor,
       COUNT(*) AS ingressantes,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY c.nome, a.ano_ingresso, p.dimensao), 2) AS pct
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
CROSS JOIN LATERAL (VALUES
    ('genero',          a.genero),
    ('raca_etnia',      a.raca_etnia),
    ('faixa_economica', a.faixa_economica),
    ('tipo_cota',       a.tipo_cota),
    ('tipo_escola_em',  a.tipo_escola_em)
) AS p(dimensao, valor)
GROUP BY c.nome, a.ano_ingresso, p.dimensao, p.valor
ORDER BY c.nome, a.ano_ingresso, p.dimensao, pct DESC;

-- 4.2 Gap cotistas x nao cotistas: nota, reprovacao e evasao [F1 + Aluno]
SELECT 'desempenho' AS bloco,
       CASE WHEN cotista THEN 'Cotista' ELSE 'Não cotista' END AS grupo,
       COUNT(*) AS base,
       ROUND(AVG(media_nota), 2) AS media_nota,
       ROUND(100.0 * COUNT(*) FILTER (WHERE situacao <> 'Aprovado') / COUNT(*), 2) AS pct_reprovacao
FROM dm_aluno_prof.vw_aluno_disciplina
GROUP BY cotista
UNION ALL
SELECT 'evasao',
       CASE WHEN a.tipo_cota <> 'Ampla Concorrência' THEN 'Cotista' ELSE 'Não cotista' END,
       COUNT(*),
       NULL,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2)
FROM dm_aluno_prof.dim_aluno a
GROUP BY a.tipo_cota <> 'Ampla Concorrência'
ORDER BY bloco, grupo;

-- 4.5 Perfil geográfico
WITH auxilios AS ( 
    SELECT aluno_id, tipo_auxilio, MIN(data_inicio) AS primeiro_auxilio
    FROM dm_aluno_prof.aluno_auxilio
    GROUP BY aluno_id, tipo_auxilio),
base AS ( 
    SELECT x.tipo_auxilio,
        CASE
            WHEN v.data_completa < x.primeiro_auxilio
                THEN 'Antes do auxílio'
            ELSE 'A partir do auxílio'
        END AS periodo, v.aluno_id, v.media_nota, v.situacao
    FROM dm_aluno_prof.vw_aluno_disciplina v
    JOIN auxilios x ON x.aluno_id = v.aluno_id
)
SELECT tipo_auxilio, periodo,
    COUNT(*) AS matriculas,
    COUNT(DISTINCT aluno_id) AS alunos,
    ROUND( AVG(media_nota), 2 ) AS media_nota,
    ROUND( 100.0 * COUNT(*) FILTER (WHERE situacao IN ( 'Reprovado por Nota', 'Reprovado por Falta')) / NULLIF(COUNT(*), 0), 2 ) AS pct_reprovacao
FROM base
GROUP BY tipo_auxilio, periodo
ORDER BY tipo_auxilio, periodo;


-- ############################################################################
-- 5. DOCENCIA E TURMAS   [F2 + Professor]
-- (professores de uma turma = sk_p1, sk_p2 e sk_p3; cada um recebe a turma inteira)
-- ############################################################################

-- Base: uma linha por turma x professor
CREATE OR REPLACE VIEW dm_prof.vw_rend_prof_turma AS
SELECT r.*, p.professor_id, p.nome AS professor, p.genero AS prof_genero, p.faixa_etaria AS prof_faixa_etaria,
       p.raca_etnia AS prof_raca_etnia, p.regime_trabalho, p.titulacao
FROM dm_prof.vw_rend_turma r
CROSS JOIN LATERAL (VALUES (r.sk_p1), (r.sk_p2), (r.sk_p3)) AS s(pid)
JOIN dm_prof.dim_professor p ON p.professor_id = s.pid;

-- 5.1 Rendimento medio por professor (aprovacao, nota, faltas) - ponderado pelos matriculados
SELECT professor_id, professor, regime_trabalho, titulacao,
    COUNT(DISTINCT turma_id) AS turmas,
    SUM(qtd_matriculados) AS matriculas_atribuidas,
    ROUND( 100.0 * SUM(qtd_aprn)/ NULLIF(SUM(qtd_matriculados), 0),2) AS pct_aprovacao,
    ROUND(SUM(media_notas * qtd_matriculados)/ NULLIF(SUM(qtd_matriculados), 0),2) AS media_nota,
    ROUND(SUM(media_faltas * qtd_matriculados)/ NULLIF(SUM(qtd_matriculados), 0),2) AS media_faltas
FROM dm_prof.vw_rend_prof_turma
GROUP BY professor_id, professor, regime_trabalho, titulacao
ORDER BY pct_aprovacao;


-- 5.2 Professores com maior variacao de aprovacao entre turmas da mesma disciplina
SELECT professor_id, professor, codigo_disciplina,disciplina,
    COUNT(DISTINCT turma_id) AS turmas,
    ROUND(MIN(prct_aprovados),2) AS menor_aprovacao,
    ROUND(MAX(prct_aprovados),2) AS maior_aprovacao,
    ROUND(AVG(prct_aprovados),2) AS media_aprovacao,
    ROUND(STDDEV_POP(prct_aprovados),2) AS desvio_aprovacao
FROM dm_prof.vw_rend_prof_turma
GROUP BY professor_id, professor, codigo_disciplina, disciplina
HAVING COUNT(DISTINCT turma_id) >= 2
ORDER BY desvio_aprovacao DESC
LIMIT 50;

-- 5.5 Turmas com baixa matricula (menos de 15 alunos ou menos de 60% das vagas)
SELECT ano_semestre, curso, codigo_disciplina, disciplina, codigo_turma,
       qtd_matriculados, vagas_ofertadas,
       ROUND(100.0 * qtd_matriculados / vagas_ofertadas, 1) AS pct_ocupacao
FROM dm_prof.vw_rend_turma
WHERE qtd_matriculados < 15 OR qtd_matriculados < 0.6 * vagas_ofertadas
ORDER BY pct_ocupacao;

-- 5.7 Professores com alto % de reprovacao por falta (acima da media geral + 1 desvio)
WITH prof AS (
    SELECT professor_id, professor, regime_trabalho,
           SUM(qtd_matriculados) AS alunos,
           100.0 * SUM(qtd_rprf) / SUM(qtd_matriculados) AS pct_rprf
    FROM dm_prof.vw_rend_prof_turma
    GROUP BY professor_id, professor, regime_trabalho
    HAVING SUM(qtd_matriculados) >= 100
)
SELECT professor_id, professor, regime_trabalho, alunos,
       ROUND(pct_rprf, 2) AS pct_reprov_falta,
       ROUND(AVG(pct_rprf) OVER (), 2) AS media_geral
FROM prof
WHERE pct_rprf > (SELECT AVG(pct_rprf) + STDDEV_POP(pct_rprf) FROM prof)
ORDER BY pct_rprf DESC;


-- ############################################################################
-- 6. CONSULTAS POR PERFIL DE GESTOR (as que nao repetem as acima)
-- ############################################################################

-- 6.1 Coordenador: meu curso x cursos similares de outros campi (ex.: Design x Design (Agreste))
WITH base AS (
    SELECT regexp_replace(c.nome, ' \(.*\)$', '') AS curso_base, c.nome AS curso, c.campi, c.curso_id
    FROM dm_aluno_prof.dim_curso c
)
SELECT b.curso_base, b.curso, b.campi,
       COUNT(DISTINCT a.aluno_id) AS alunos,
       ROUND(100.0 * COUNT(DISTINCT a.aluno_id) FILTER (WHERE a.tipo_evasao <> 'Ativo') / NULLIF(COUNT(DISTINCT a.aluno_id), 0), 2) AS taxa_evasao,
       ROUND(100.0 * SUM(CASE WHEN f.situacao = 'Aprovado' THEN 1 ELSE 0 END) / NULLIF(COUNT(f.aluno_id), 0), 2) AS pct_aprovacao,
       ROUND(AVG(f.media_nota), 2) AS media_nota
FROM base b
JOIN dm_aluno_prof.dim_aluno a ON a.curso_id = b.curso_id
LEFT JOIN dm_aluno_prof.fato_aluno_em_disciplina f ON f.aluno_id = a.aluno_id
WHERE b.curso_base IN (SELECT curso_base FROM base GROUP BY curso_base HAVING COUNT(*) > 1)
GROUP BY b.curso_base, b.curso, b.campi
ORDER BY b.curso_base, b.campi;

-- 6.2 Diretor de departamento: ranking das disciplinas do departamento por reprovacao,
--     marcando as que atendem alunos de OUTROS cursos ("disciplinas de servico") [F1]
--     AVISO: neste volume cada disciplina so atende o proprio curso (a coluna de servico fica zerada);
--     para capturar servico de verdade falta a tabela ponte curso x disciplina (item 5 do topico 7)
SELECT v.departamento, v.codigo_disciplina, v.disciplina,
       COUNT(*) AS matriculas,
       COUNT(*) FILTER (WHERE a.curso_id <> v.curso_id) AS matriculas_de_outros_cursos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE v.situacao <> 'Aprovado') / COUNT(*), 2) AS pct_reprovacao
FROM dm_aluno_prof.vw_aluno_disciplina v
JOIN dm_aluno_prof.dim_aluno a ON a.aluno_id = v.aluno_id
GROUP BY v.departamento, v.codigo_disciplina, v.disciplina
ORDER BY v.departamento, pct_reprovacao DESC;

-- 6.3 Pro-reitor: disciplinas de ciclo basico (1o e 2o periodos) que mais retem em toda a universidade [F2]
SELECT disciplina,
       COUNT(DISTINCT curso) AS cursos_que_ofertam,
       SUM(qtd_matriculados) AS matriculas,
       ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprovacao
FROM dm_prof.vw_rend_turma
WHERE periodo <= 2
GROUP BY disciplina
HAVING SUM(qtd_matriculados) >= 100
ORDER BY pct_reprovacao DESC;

-- 6.4 Reitor / Pro-reitor: painel institucional por ano e campus
--     evasao, taxa de sucesso (formados), reprovacao e diversidade
--     (a comparacao com eventos externos - pandemia, greves, cotas - exigiria um calendario de eventos na dim_data)
WITH rep AS (
    SELECT ano, campi,
           ROUND(100.0 * SUM(total_reprovados) / SUM(qtd_matriculados), 2) AS pct_reprovacao_geral
    FROM dm_prof.vw_rend_turma GROUP BY ano, campi
), ing AS (
    SELECT a.ano_ingresso AS ano, c.campi,
           COUNT(*) AS ingressantes,
           ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao_coorte,
           ROUND(100.0 * COUNT(*) FILTER (WHERE a.raca_etnia IN ('Parda', 'Preta', 'Indígena')) / COUNT(*), 1) AS pct_ppi,
           ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_cota <> 'Ampla Concorrência') / COUNT(*), 1)            AS pct_cotistas
    FROM dm_aluno_prof.dim_aluno a
    JOIN dm_aluno_prof.dim_curso c ON c.curso_id = a.curso_id
    GROUP BY a.ano_ingresso, c.campi
)
SELECT COALESCE(i.ano, r.ano) AS ano, COALESCE(i.campi, r.campi) AS campus,
       i.ingressantes, i.taxa_evasao_coorte, r.pct_reprovacao_geral, i.pct_ppi, i.pct_cotistas
FROM ing i
FULL JOIN rep r ON r.ano = i.ano AND r.campi = i.campi
ORDER BY ano, campus;


-- ############################################################################
-- 7. CONSULTAS EXTRAS QUE USAM OS METADADOS DO TOPICO 8
-- ############################################################################

-- 7.1 Conceito ENADE x rendimento e evasao por curso [Curso + F2 + Aluno]
SELECT c.nome AS curso, c.conceito_enade,
       ROUND(100.0 * SUM(r.qtd_aprn) / SUM(r.qtd_matriculados), 2) AS pct_aprovacao,
       ROUND(SUM(r.media_notas * r.qtd_matriculados) / SUM(r.qtd_matriculados), 2) AS media_nota,
       ev.taxa_evasao
FROM dm_prof.dim_curso c
JOIN dm_prof.fato_rend_disciplina r ON r.curso_id = c.curso_id
JOIN (SELECT curso_id,
             ROUND(100.0 * COUNT(*) FILTER (WHERE tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao
      FROM dm_aluno_prof.dim_aluno GROUP BY curso_id) ev ON ev.curso_id = c.curso_id
GROUP BY c.nome, c.conceito_enade, ev.taxa_evasao
ORDER BY c.conceito_enade DESC, pct_aprovacao DESC;

-- 7.2 Avaliacao docente x rendimento por professor [avaliacao_docente + F2]
SELECT p.professor_id, p.nome AS professor, p.regime_trabalho, p.titulacao,
       COUNT(*) AS turmas_avaliadas,
       ROUND(SUM(av.nota_media * av.qtd_respondentes) / SUM(av.qtd_respondentes), 2) AS avaliacao_media,
       ROUND(100.0 * SUM(r.qtd_aprn) / SUM(r.qtd_matriculados), 2) AS pct_aprovacao
FROM dm_prof.avaliacao_docente av
JOIN dm_prof.dim_professor p ON p.professor_id = av.professor_id
JOIN dm_prof.fato_rend_disciplina r ON r.turma_id = av.turma_id
GROUP BY p.professor_id, p.nome, p.regime_trabalho, p.titulacao
HAVING COUNT(*) >= 3
ORDER BY avaliacao_media DESC;

-- 7.2b Correlacao global entre avaliacao docente e aprovacao da turma, por titulacao
SELECT p.titulacao,
       COUNT(*) AS avaliacoes,
       ROUND(AVG(av.nota_media), 2) AS avaliacao_media,
       ROUND(CORR(av.nota_media, r.prct_aprovados)::numeric, 3) AS correlacao_avaliacao_aprovacao
FROM dm_prof.avaliacao_docente av
JOIN dm_prof.dim_professor p ON p.professor_id = av.professor_id
JOIN dm_prof.fato_rend_disciplina r ON r.turma_id = av.turma_id
GROUP BY p.titulacao
ORDER BY p.titulacao;

-- 7.3 Atividades extracurriculares x rendimento e evasao [aluno_atividade_extra + F1 + Aluno]
SELECT COALESCE(ae.tipo_atividade, 'Sem atividade') AS tipo_atividade,
       COUNT(DISTINCT a.aluno_id) AS alunos,
       ROUND(100.0 * COUNT(DISTINCT a.aluno_id) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(DISTINCT a.aluno_id), 2) AS taxa_evasao,
       ROUND(AVG(f.media_nota), 2) AS media_nota,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.situacao = 'Aprovado') / COUNT(*), 2) AS pct_aprovacao
FROM dm_aluno_prof.dim_aluno a
LEFT JOIN dm_aluno_prof.aluno_atividade_extra ae ON ae.aluno_id = a.aluno_id
JOIN dm_aluno_prof.fato_aluno_em_disciplina f ON f.aluno_id = a.aluno_id
GROUP BY COALESCE(ae.tipo_atividade, 'Sem atividade')
ORDER BY tipo_atividade;

-- 7.4 Deslocamento x evasao e rendimento por faixa de tempo de deslocamento [Aluno + F1]
SELECT CASE WHEN a.tempo_deslocamento_min < 30 THEN '1) < 30 min'
            WHEN a.tempo_deslocamento_min < 60 THEN '2) 30-59 min'
            WHEN a.tempo_deslocamento_min < 90 THEN '3) 60-89 min'
            ELSE '4) 90+ min' END AS faixa_deslocamento,
       COUNT(DISTINCT a.aluno_id) AS alunos,
       ROUND(100.0 * COUNT(DISTINCT a.aluno_id) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(DISTINCT a.aluno_id), 2) AS taxa_evasao,
       ROUND(AVG(f.media_nota), 2) AS media_nota,
       ROUND(AVG(f.qtd_faltas::numeric / d.carga_horaria) * 100, 2) AS pct_faltas_medio
FROM dm_aluno_prof.dim_aluno a
JOIN dm_aluno_prof.fato_aluno_em_disciplina f ON f.aluno_id = a.aluno_id
JOIN dm_aluno_prof.dim_disciplina d ON d.disciplina_id = f.disciplina_id
GROUP BY 1
ORDER BY 1;

-- 7.5 Valor e tipo de auxilio x permanencia [aluno_auxilio + Aluno]
SELECT x.tipo_auxilio, x.valor_mensal,
       COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.tipo_evasao <> 'Ativo') / COUNT(*), 2) AS taxa_evasao,
       ROUND(AVG(a.ch_integralizada), 0) AS ch_media_integralizada
FROM dm_aluno_prof.aluno_auxilio x
JOIN dm_aluno_prof.dim_aluno a ON a.aluno_id = x.aluno_id
GROUP BY x.tipo_auxilio, x.valor_mensal
ORDER BY x.tipo_auxilio;

-- 7.6 Situacao de matricula por semestre (visao de coorte: ativos, trancados, cancelados) [fato_matricula_periodo]
SELECT dt.ano_semestre, m.situacao, COUNT(*) AS alunos,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY dt.ano_semestre), 2) AS pct_no_semestre
FROM dm_aluno_prof.fato_matricula_periodo m
JOIN dm_aluno_prof.dim_data dt ON dt.tempo_id = m.tempo_id
GROUP BY dt.ano_semestre, m.situacao
ORDER BY dt.ano_semestre, m.situacao;
