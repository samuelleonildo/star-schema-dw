-- ============================================================================
-- POVOAMENTO DO DATA MART (UFPE) - VERSAO CORRIGIDA
-- Schemas: dm_aluno_prof e dm_prof
--
-- COMO RODAR:
--   * Rode o script INTEIRO numa unica sessao/conexao (usa tabelas e funcoes
--     temporarias, que somem ao fechar a conexao).
--   * O bloco 0 faz TRUNCATE ... RESTART IDENTITY nas tabelas do data mart,
--     pois o script assume ids sequenciais comecando em 1.
--
-- PREMISSAS:
--   * Campi reais da UFPE: Recife, Caruaru (CAA) e Vitoria de Santo Antao (CAV).
--   * media_nota = media FINAL (apos exame final, quando houve).
--     Regra UFPE: media >= 7 aprova; 3 a 6,9 vai a exame e precisa de media
--     final >= 5; < 3 reprova. Logo, "media_nota >= 5" aprova.
--   * Reprovacao por falta: faltas > 25% da carga horaria (1 falta = 1 hora).
--   * 1 credito = 15 horas.
--   * Cada curso tem 20 disciplinas modeladas (nao e o curriculo completo).
--   * Alunos ingressam de 2023.1 a 2026.1; ha turmas de 2023.1 a 2026.1.
--   * Os dados sao sinteticos, mas coerentes entre si (aluno x curso x
--     disciplina x turma x professor x campus x data).
-- ============================================================================

SELECT setseed(0.2026);

-- ----------------------------------------------------------------------------
-- 0. LIMPEZA (garante ids a partir de 1)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE
    dm_prof.fato_rend_disciplina,
    dm_prof.dim_turma_disciplina,
    dm_prof.dim_disciplina,
    dm_prof.dim_data,
    dm_prof.dim_professor,
    dm_prof.dim_curso,
    dm_aluno_prof.fato_aluno_em_disciplina,
    dm_aluno_prof.dim_turma_disciplina,
    dm_aluno_prof.dim_disciplina,
    dm_aluno_prof.dim_aluno,
    dm_aluno_prof.dim_data,
    dm_aluno_prof.dim_professor,
    dm_aluno_prof.dim_curso
RESTART IDENTITY CASCADE;

-- ----------------------------------------------------------------------------
-- 0.1 FUNCOES AUXILIARES (temporarias)
-- ----------------------------------------------------------------------------

-- Nome coerente com o genero: i par = masculino, i impar = feminino
CREATE OR REPLACE FUNCTION pg_temp.gen_genero(i int) RETURNS text AS $$
    SELECT CASE WHEN i % 2 = 0 THEN 'Masculino' ELSE 'Feminino' END
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION pg_temp.gen_nome(i int) RETURNS text AS $$
    SELECT CASE WHEN i % 2 = 0
             THEN (ARRAY['João','Pedro','Lucas','Gabriel','Matheus','Rafael','Felipe','Gustavo','Bruno','Thiago','Carlos','Marcos','Roberto','Paulo','Ricardo'])[1 + (i / 2) % 15]
             ELSE (ARRAY['Maria','Ana','Beatriz','Larissa','Camila','Júlia','Mariana','Letícia','Amanda','Isabela','Fernanda','Juliana','Patrícia','Aline','Renata'])[1 + (i / 2) % 15]
           END
        || ' ' || (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Ferreira','Almeida','Nascimento','Lima','Barbosa','Rodrigues','Carvalho','Gomes'])[1 + (i * 5) % 14]
        || ' ' || (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Ferreira','Almeida','Nascimento','Lima','Barbosa','Rodrigues','Carvalho','Gomes'])[1 + (i / 14 + i * 3) % 14]
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION pg_temp.gen_raca(i int) RETURNS text AS $$
    SELECT CASE WHEN i % 50 = 0  THEN 'Indígena'
                WHEN i % 20 < 9  THEN 'Branca'
                WHEN i % 20 < 17 THEN 'Parda'
                WHEN i % 20 < 19 THEN 'Preta'
                ELSE 'Amarela' END
$$ LANGUAGE sql IMMUTABLE;

-- Bairro e naturalidade coerentes com o campus do curso
CREATE OR REPLACE FUNCTION pg_temp.gen_bairro(campi text, i int) RETURNS text AS $$
    SELECT CASE campi
        WHEN 'Campus Caruaru' THEN
            (ARRAY['Centro','Maurício de Nassau','Indianópolis','Universitário','Petrópolis','Nova Caruaru','Salgado','Vassoural'])[1 + i % 8]
        WHEN 'Campus Vitória de Santo Antão' THEN
            (ARRAY['Centro','Livramento','Matriz','Redenção','Maués','Bela Vista'])[1 + i % 6]
        ELSE
            (ARRAY['Boa Viagem','Graças','Torre','Pina','Madalena','Casa Forte','Derby','Várzea','Cordeiro','Iputinga'])[1 + i % 10]
    END
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION pg_temp.gen_naturalidade(campi text, i int) RETURNS text AS $$
    SELECT CASE campi
        WHEN 'Campus Caruaru' THEN
            (ARRAY['Caruaru','Caruaru','Bezerros','Gravatá','Toritama','Santa Cruz do Capibaribe','Agrestina','Belo Jardim'])[1 + i % 8]
        WHEN 'Campus Vitória de Santo Antão' THEN
            (ARRAY['Vitória de Santo Antão','Vitória de Santo Antão','Chã Grande','Pombos','Glória do Goitá','Lagoa de Itaenga'])[1 + i % 6]
        ELSE
            (ARRAY['Recife','Recife','Recife','Olinda','Jaboatão dos Guararapes','Paulista','Camaragibe','Cabo de Santo Agostinho'])[1 + i % 8]
    END
$$ LANGUAGE sql IMMUTABLE;

-- CPF ficticio, porem com digitos verificadores validos (n deve ser unico)
CREATE OR REPLACE FUNCTION pg_temp.gen_cpf(n bigint) RETURNS text AS $$
DECLARE
    base text;
    s int;
    k int;
BEGIN
    base := LPAD(((n * 7919 + 123456789) % 1000000000)::text, 9, '0');
    s := 0;
    FOR k IN 1..9 LOOP
        s := s + substr(base, k, 1)::int * (11 - k);
    END LOOP;
    s := ((s * 10) % 11) % 10;
    base := base || s::text;
    s := 0;
    FOR k IN 1..10 LOOP
        s := s + substr(base, k, 1)::int * (12 - k);
    END LOOP;
    s := ((s * 10) % 11) % 10;
    RETURN base || s::text;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 0.2 CURSOS (tabela temporaria de apoio) - campi/centros reais da UFPE
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_curso (
    seq               serial,
    nome              text,
    departamento      text,
    centro            text,
    campi             text,
    duracao           int,
    turno             text,
    modalidade_curso  text,
    modalidade_ensino text,
    tmin              int,
    tmax              int,
    curriculo         text,
    ch                int,
    area              int,   -- 1 Computacao, 2 Engenharia, 3 Saude/Bio, 4 Humanas, 5 Gestao, 6 Exatas, 7 Design
    blocado           boolean
);

INSERT INTO tmp_curso
    (nome, departamento, centro, campi, duracao, turno, modalidade_curso, modalidade_ensino, tmin, tmax, curriculo, ch, area, blocado)
VALUES
-- ===== Campus Recife =====
('Ciência da Computação',            'Centro de Informática',                    'CIn',  'Campus Recife', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2023.1', 3200, 1, FALSE),
('Engenharia da Computação',         'Centro de Informática',                    'CIn',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2023.1', 3800, 1, FALSE),
('Sistemas de Informação',           'Centro de Informática',                    'CIn',  'Campus Recife', 8,  'Noturno',  'Bacharelado', 'Presencial', 8,  14, '2023.1', 3000, 1, FALSE),
('Engenharia Civil',                 'Departamento de Engenharia Civil',         'CTG',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 2, FALSE),
('Engenharia Mecânica',              'Departamento de Engenharia Mecânica',      'CTG',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 2, FALSE),
('Engenharia Elétrica',              'Departamento de Engenharia Elétrica',      'CTG',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 3900, 2, FALSE),
('Engenharia Química',               'Departamento de Engenharia Química',       'CTG',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 2, FALSE),
('Medicina',                         'Departamento de Medicina Clínica',         'CCM',  'Campus Recife', 12, 'Integral', 'Bacharelado', 'Presencial', 12, 18, '2021.1', 8500, 3, TRUE),
('Enfermagem',                       'Departamento de Enfermagem',               'CCS',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4100, 3, FALSE),
('Odontologia',                      'Departamento de Clínica e Odontologia Preventiva', 'CCS', 'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 3, FALSE),
('Farmácia',                         'Departamento de Ciências Farmacêuticas',   'CCS',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 3, FALSE),
('Direito',                          'Departamento de Direito',                  'CCJ',  'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2023.1', 3700, 4, FALSE),
('Administração',                    'Departamento de Ciências Administrativas', 'CCSA', 'Campus Recife', 8,  'Noturno',  'Bacharelado', 'Presencial', 8,  14, '2022.1', 3000, 5, FALSE),
('Ciências Contábeis',               'Departamento de Ciências Contábeis e Atuariais', 'CCSA', 'Campus Recife', 8, 'Noturno', 'Bacharelado', 'Presencial', 8, 14, '2022.1', 3000, 5, FALSE),
('Economia',                         'Departamento de Economia',                 'CCSA', 'Campus Recife', 8,  'Noturno',  'Bacharelado', 'Presencial', 8,  14, '2022.1', 3000, 5, FALSE),
('Psicologia',                       'Departamento de Psicologia',               'CFCH', 'Campus Recife', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2022.1', 4000, 4, FALSE),
('História',                         'Departamento de História',                 'CFCH', 'Campus Recife', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2022.1', 3000, 4, FALSE),
('Geografia',                        'Departamento de Ciências Geográficas',     'CFCH', 'Campus Recife', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2022.1', 2900, 4, FALSE),
('Design',                           'Departamento de Design',                   'CAC',  'Campus Recife', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2022.1', 3100, 7, FALSE),
('Pedagogia',                        'Departamento de Métodos e Técnicas de Ensino', 'CE', 'Campus Recife', 8, 'Noturno', 'Licenciatura','Presencial', 8,  14, '2022.1', 3200, 4, FALSE),
('Matemática',                       'Departamento de Matemática',               'CCEN', 'Campus Recife', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2022.1', 2800, 6, FALSE),
('Física',                           'Departamento de Física',                   'CCEN', 'Campus Recife', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2022.1', 2900, 6, FALSE),
('Química',                          'Departamento de Química Fundamental',      'CCEN', 'Campus Recife', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2022.1', 2850, 6, FALSE),
('Ciências Biológicas',              'Departamento de Zoologia',                 'CB',   'Campus Recife', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2022.1', 3200, 3, FALSE),
-- ===== Campus Caruaru (CAA) - organizado em Nucleos =====
('Engenharia Civil (Agreste)',       'Núcleo de Tecnologia',                     'CAA',  'Campus Caruaru', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2023.1', 3900, 2, FALSE),
('Engenharia de Produção (Agreste)', 'Núcleo de Tecnologia',                     'CAA',  'Campus Caruaru', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2023.1', 3900, 2, FALSE),
('Design (Agreste)',                 'Núcleo de Design e Comunicação',           'CAA',  'Campus Caruaru', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2023.1', 3000, 7, FALSE),
('Administração (Agreste)',          'Núcleo de Gestão',                         'CAA',  'Campus Caruaru', 8,  'Noturno',  'Bacharelado', 'Presencial', 8,  14, '2023.1', 3000, 5, FALSE),
('Economia (Agreste)',               'Núcleo de Gestão',                         'CAA',  'Campus Caruaru', 8,  'Noturno',  'Bacharelado', 'Presencial', 8,  14, '2023.1', 2900, 5, FALSE),
('Pedagogia (Agreste)',              'Núcleo de Formação Docente',               'CAA',  'Campus Caruaru', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2023.1', 2800, 4, FALSE),
('Matemática (Agreste)',             'Núcleo de Formação Docente',               'CAA',  'Campus Caruaru', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2023.1', 2800, 6, FALSE),
('Física (Agreste)',                 'Núcleo de Formação Docente',               'CAA',  'Campus Caruaru', 8,  'Noturno',  'Licenciatura','Presencial', 8,  14, '2023.1', 2850, 6, FALSE),
-- ===== Campus Vitoria de Santo Antao (CAV) =====
('Educação Física (Vitória)',        'Núcleo de Educação Física',                'CAV',  'Campus Vitória de Santo Antão', 8,  'Integral', 'Licenciatura/Bacharelado', 'Presencial', 8,  14, '2023.1', 3200, 3, FALSE),
('Enfermagem (Vitória)',             'Núcleo de Enfermagem',                     'CAV',  'Campus Vitória de Santo Antão', 10, 'Integral', 'Bacharelado', 'Presencial', 10, 16, '2023.1', 4100, 3, FALSE),
('Nutrição (Vitória)',               'Núcleo de Nutrição',                       'CAV',  'Campus Vitória de Santo Antão', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2023.1', 3400, 3, FALSE),
('Saúde Coletiva (Vitória)',         'Núcleo de Saúde Coletiva',                 'CAV',  'Campus Vitória de Santo Antão', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2023.1', 3100, 3, FALSE),
('Ciências Biológicas (Vitória)',    'Núcleo de Biologia',                       'CAV',  'Campus Vitória de Santo Antão', 8,  'Integral', 'Bacharelado', 'Presencial', 8,  14, '2023.1', 3200, 3, FALSE);

-- Parametros globais do povoamento
CREATE TEMP TABLE tmp_param AS
SELECT (SELECT COUNT(*) FROM tmp_curso)::int AS n_cursos,
       400::int  AS n_prof,
       6000::int AS n_alunos;

-- ----------------------------------------------------------------------------
-- 0.3 POOL DE NOMES DE DISCIPLINAS POR AREA (20 por area; k multiplo de 5 = optativa)
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_pool (area int, k int, nome text);

INSERT INTO tmp_pool SELECT 1, ord, nome FROM unnest(ARRAY[
 'Introdução à Programação','Cálculo 1','Lógica para Computação','Algoritmos e Estruturas de Dados','Optativa: Tópicos em Computação',
 'Álgebra Linear','Matemática Discreta','Programação Orientada a Objetos','Arquitetura de Computadores','Optativa: Computação Gráfica',
 'Banco de Dados','Redes de Computadores','Sistemas Operacionais','Engenharia de Software','Optativa: Inteligência Artificial',
 'Teoria da Computação','Compiladores','Segurança da Informação','Projeto de Desenvolvimento de Software','Optativa: Tópicos Avançados']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 2, ord, nome FROM unnest(ARRAY[
 'Cálculo Diferencial e Integral 1','Física Geral 1','Química Geral','Geometria Analítica','Optativa: Tópicos Especiais em Engenharia',
 'Cálculo Diferencial e Integral 2','Física Geral 2','Programação para Engenharia','Mecânica Geral','Optativa: Energias Renováveis',
 'Resistência dos Materiais','Termodinâmica','Fenômenos de Transporte','Estatística e Probabilidade','Optativa: Gestão de Projetos',
 'Materiais de Construção e Fabricação','Instrumentação e Controle','Economia para Engenharia','Estágio Supervisionado','Optativa: Empreendedorismo']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 3, ord, nome FROM unnest(ARRAY[
 'Anatomia Humana','Biologia Celular','Bioquímica','Histologia','Optativa: Tópicos em Saúde',
 'Fisiologia','Microbiologia','Imunologia','Parasitologia','Optativa: Libras',
 'Farmacologia','Patologia Geral','Bioestatística','Epidemiologia','Optativa: Saúde Mental',
 'Saúde e Sociedade','Ética e Bioética','Metodologia Científica','Estágio Supervisionado','Optativa: Educação em Saúde']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 4, ord, nome FROM unnest(ARRAY[
 'Introdução ao Estudo da Área','Teoria Social','Filosofia','Metodologia da Pesquisa','Optativa: Libras',
 'Sociologia','História do Brasil','Antropologia','Ciência Política','Optativa: Tópicos Especiais',
 'Estatística Aplicada','Teorias Contemporâneas','Ética','Pesquisa Qualitativa','Optativa: Direitos Humanos',
 'Seminário Temático','Estágio Supervisionado 1','Estágio Supervisionado 2','Trabalho de Conclusão de Curso','Optativa: Educação e Sociedade']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 5, ord, nome FROM unnest(ARRAY[
 'Introdução à Administração','Matemática Básica','Contabilidade Introdutória','Microeconomia','Optativa: Libras',
 'Macroeconomia','Estatística','Direito Empresarial','Cálculo para Gestão','Optativa: Empreendedorismo',
 'Matemática Financeira','Marketing','Gestão de Pessoas','Métodos Quantitativos','Optativa: Finanças Pessoais',
 'Contabilidade de Custos','Economia Brasileira','Administração Financeira','Metodologia Científica','Optativa: Tópicos em Gestão']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 6, ord, nome FROM unnest(ARRAY[
 'Cálculo 1','Geometria Analítica','Fundamentos de Matemática Elementar','Física Geral 1','Optativa: Libras',
 'Cálculo 2','Álgebra Linear','Física Geral 2','Química Geral','Optativa: História da Ciência',
 'Cálculo 3','Probabilidade e Estatística','Equações Diferenciais','Didática','Optativa: Tópicos em Ensino de Ciências',
 'Computação Científica','Metodologia do Ensino','Estágio Supervisionado 1','Estágio Supervisionado 2','Optativa: Tópicos Especiais']
) WITH ORDINALITY AS t(nome, ord);

INSERT INTO tmp_pool SELECT 7, ord, nome FROM unnest(ARRAY[
 'Fundamentos do Design','Desenho de Observação','Teoria da Cor','História do Design','Optativa: Libras',
 'Design Gráfico','Tipografia','Metodologia de Projeto','Ergonomia','Optativa: Fotografia',
 'Design de Interação','Design de Produto','Materiais e Processos','Design de Embalagem','Optativa: Animação',
 'Semiótica','Projeto de Design','Design e Sustentabilidade','Trabalho de Conclusão de Curso','Optativa: Empreendedorismo Criativo']
) WITH ORDINALITY AS t(nome, ord);


-- ============================================================================
-- 1. CARGA - SCHEMA: dm_aluno_prof
-- ============================================================================

-- 1.1 DIM_Curso
INSERT INTO dm_aluno_prof.dim_curso (
    nome, departamento, centro, campi, duracao, turno,
    modalidade_curso, modalidade_ensino, tempo_min_conclusao,
    tempo_max_conclusao, curriculo, carga_horaria
)
SELECT nome, departamento, centro, campi, duracao, turno,
       modalidade_curso, modalidade_ensino, tmin, tmax, curriculo, ch
FROM tmp_curso
ORDER BY seq;

-- 1.2 DIM_Professor: 400 professores, cada um lotado em um curso/campus
--     (professor i pertence ao curso 1 + (i-1) mod n_cursos)
INSERT INTO dm_aluno_prof.dim_professor (
    numero_matricula, nome, data_nascimento, faixa_etaria, genero,
    raca_etnia, bairro_residencia, cpf, nacionalidade, naturalidade,
    nome_mae, nome_pai, estado_civil, deficiencia
)
SELECT
    LPAD((1400000 + t.i * 13)::text, 7, '0'),                 -- SIAPE: 7 digitos
    pg_temp.gen_nome(t.i),
    t.nasc,
    CASE WHEN t.idade <= 34 THEN '28-34'
         WHEN t.idade <= 44 THEN '35-44'
         WHEN t.idade <= 54 THEN '45-54'
         ELSE '55+' END,                                       -- derivada da data de nascimento
    pg_temp.gen_genero(t.i),
    pg_temp.gen_raca(t.i),
    pg_temp.gen_bairro(t.campi, t.i),
    pg_temp.gen_cpf(t.i),
    'Brasileira',
    pg_temp.gen_naturalidade(t.campi, t.i),
    pg_temp.gen_nome(t.i * 2 + 1),                             -- nome feminino
    pg_temp.gen_nome(t.i * 2),                                 -- nome masculino
    CASE WHEN t.idade < 32 THEN 'Solteiro(a)'
         ELSE (ARRAY['Casado(a)','Casado(a)','Solteiro(a)','Divorciado(a)','União Estável'])[1 + t.i % 5] END,
    CASE WHEN t.i % 25 = 0 THEN 'Física'
         WHEN t.i % 40 = 7 THEN 'Visual'
         ELSE 'Nenhuma' END
FROM (
    SELECT b.*, date_part('year', age(DATE '2026-11-01', b.nasc))::int AS idade
    FROM (
        SELECT g.i, c.campi,
               (DATE '2026-11-01' - ((28 + (g.i * 7) % 43) * 365 + (g.i * 37) % 365)) AS nasc
        FROM generate_series(1, (SELECT n_prof FROM tmp_param)) AS g(i)
        JOIN tmp_curso c ON c.seq = 1 + (g.i - 1) % (SELECT n_cursos FROM tmp_param)
    ) b
) t
ORDER BY t.i;

-- 1.3 DIM_Data: 1.461 dias (2023-01-01 a 2026-12-31), em ordem cronologica
INSERT INTO dm_aluno_prof.dim_data (
    data_completa, semestre, ano, ano_semestre
)
SELECT
    dt::date,
    CASE WHEN EXTRACT(MONTH FROM dt) <= 6 THEN 1 ELSE 2 END,
    EXTRACT(YEAR FROM dt)::int,
    EXTRACT(YEAR FROM dt)::text || '.' || (CASE WHEN EXTRACT(MONTH FROM dt) <= 6 THEN 1 ELSE 2 END)::text
FROM (
    SELECT DATE '2023-01-01' + (i - 1) AS dt
    FROM generate_series(1, 1461) AS s(i)
) sub
ORDER BY dt;

-- 1.4 DIM_Disciplina: 20 disciplinas por curso, com nome real da area,
--     CH/creditos coerentes (1 credito = 15h), periodo distribuido pela duracao do curso,
--     horario compativel com o turno do curso.
INSERT INTO dm_aluno_prof.dim_disciplina (
    codigo_disciplina, nome, carga_horaria, creditos, periodo, fk_curso, tipo, horario
)
SELECT
    'DISC-' || LPAD(((c.seq - 1) * 20 + p.k)::text, 4, '0'),
    p.nome,
    ch.v,
    ch.v / 15,
    1 + ((p.k - 1) * c.duracao) / 20,
    c.seq,
    CASE WHEN p.k % 5 = 0 THEN 'Optativa' ELSE 'Obrigatória' END,
    CASE WHEN c.turno LIKE '%Noturno%'
         THEN (ARRAY['SEG/QUA 18:50-20:30','TER/QUI 18:50-20:30','SEG/QUA 20:30-22:10','TER/QUI 20:30-22:10'])[1 + p.k % 4]
         ELSE (ARRAY['SEG/QUA 08:00-10:00','TER/QUI 10:00-12:00','SEG/QUA 14:00-16:00','TER/QUI 14:00-16:00'])[1 + p.k % 4]
    END
FROM tmp_curso c
JOIN tmp_pool p ON p.area = c.area
CROSS JOIN LATERAL (SELECT (ARRAY[30, 60, 60, 60, 90])[1 + p.k % 5] AS v) ch
ORDER BY c.seq, p.k;

-- 1.5 DIM_TurmaDisciplina: uma turma por disciplina e semestre (2023.1 a 2026.1),
--     apenas quando existe coorte de alunos naquele periodo.
--     Professores: sempre do MESMO curso/campus da disciplina.
CREATE TEMP TABLE tmp_turma AS
SELECT
    ROW_NUMBER() OVER (ORDER BY d.disciplina_id, m.m)::int AS turma_id,
    d.disciplina_id,
    d.fk_curso AS curso_id,
    d.periodo,
    m.m AS sem                                  -- 0 = 2023.1 ... 6 = 2026.1
FROM dm_aluno_prof.dim_disciplina d
CROSS JOIN generate_series(0, 6) AS m(m)
WHERE m.m >= d.periodo - 1;

INSERT INTO dm_aluno_prof.dim_turma_disciplina (
    codigo_turma, fk_disciplina, sk_p1, sk_p2, sk_p3
)
SELECT
    right((2023 + t.sem / 2)::text, 2) || (1 + t.sem % 2)::text || '-D' || LPAD(t.disciplina_id::text, 4, '0'),
    t.disciplina_id,
    -- professores do curso c: ids c, c+n, c+2n, ... (<= 400)
    t.curso_id + n.n_cursos * ((t.disciplina_id + t.sem) % (((n.n_prof - t.curso_id) / n.n_cursos) + 1)),
    CASE WHEN (t.disciplina_id + t.sem) % 6 = 0 AND ((n.n_prof - t.curso_id) / n.n_cursos) + 1 > 1
         THEN t.curso_id + n.n_cursos * ((t.disciplina_id + t.sem + 1) % (((n.n_prof - t.curso_id) / n.n_cursos) + 1))
         ELSE NULL END,
    NULL
FROM tmp_turma t
CROSS JOIN tmp_param n
ORDER BY t.turma_id;

-- 1.6 DIM_Aluno: 6.000 alunos, todos coerentes com o curso/campus
CREATE TEMP TABLE tmp_aluno AS
SELECT
    g.i,
    c.seq      AS curso,
    c.campi,
    c.duracao,
    c.tmin,
    c.tmax,
    c.blocado,
    (g.i % 7)  AS e,                                -- semestre de ingresso: 0 = 2023.1 ... 6 = 2026.1
    (2023 + (g.i % 7) / 2)::text || (1 + (g.i % 7) % 2)::text || LPAD(g.i::text, 5, '0') AS matricula,
    CASE WHEN g.i % 25 = 0 THEN 'Abandono'
         WHEN g.i % 40 = 1 THEN 'Transferência'
         WHEN g.i % 50 = 2 THEN 'Cancelamento'
         ELSE 'Ativo' END AS tipo_evasao,
    NULL::int  AS ev,                               -- semestre de evasao (NULL = ativo)
    random()   AS hab                               -- "habilidade" do aluno (influencia notas)
FROM generate_series(1, (SELECT n_alunos FROM tmp_param)) AS g(i)
JOIN tmp_curso c ON c.seq = 1 + (g.i - 1) % (SELECT n_cursos FROM tmp_param);

UPDATE tmp_aluno
   SET ev = LEAST(6, e + (i % 3))
 WHERE tipo_evasao <> 'Ativo';

INSERT INTO dm_aluno_prof.dim_aluno (
    numero_matricula, nome, data_nascimento, faixa_etaria, genero, raca_etnia,
    faixa_economica, cpf, curso_id, nacionalidade, naturalidade, nome_mae,
    nome_pai, estado_civil, bairro_residencia, deficiencia, ano_conclusao_em,
    semestre_ingresso, ano_semestre_ingresso, ano_ingresso, forma_ingresso,
    nivel_ensino, ch_integralizada, tipo_evasao, ano_evasao, semestre_evasao,
    qtd_min_conc, qtd_max_conc, tipo_cota, meio_ingresso, tipo_escola_em,
    assistencia_estudantil, flg_blocado
)
SELECT
    t.matricula,
    pg_temp.gen_nome(t.i),
    t.nasc,
    CASE WHEN t.idade <= 20 THEN '17-20'
         WHEN t.idade <= 24 THEN '21-24'
         WHEN t.idade <= 29 THEN '25-29'
         ELSE '30+' END,                                   -- derivada da data de nascimento
    pg_temp.gen_genero(t.i),
    pg_temp.gen_raca(t.i),
    (ARRAY['Até 1,5 SM', '1,5 a 3 SM', '3 a 5 SM'])[1 + t.i % 3],
    pg_temp.gen_cpf(100000 + t.i),
    t.curso,
    'Brasileira',
    pg_temp.gen_naturalidade(t.campi, t.i),
    pg_temp.gen_nome(t.i * 2 + 1),
    pg_temp.gen_nome(t.i * 2),
    CASE WHEN t.idade >= 28 AND t.i % 3 = 0 THEN 'Casado(a)'
         WHEN t.idade >= 25 AND t.i % 11 = 0 THEN 'União Estável'
         ELSE 'Solteiro(a)' END,
    pg_temp.gen_bairro(t.campi, t.i),
    CASE WHEN t.i % 40 = 0 THEN 'Física'
         WHEN t.i % 60 = 7 THEN 'Visual'
         WHEN t.i % 90 = 11 THEN 'Auditiva'
         ELSE 'Nenhuma' END,
    LEAST(t.y - 1, EXTRACT(YEAR FROM t.nasc)::int + 17 + t.i % 3),   -- ano de conclusao do ensino medio
    t.s,
    t.y::text || '.' || t.s::text,
    t.y,
    'SISU',
    'Graduação',
    0,                                                      -- atualizado no fim com a soma real da fato
    t.tipo_evasao,
    CASE WHEN t.ev IS NULL THEN NULL ELSE 2023 + t.ev / 2 END,
    CASE WHEN t.ev IS NULL THEN NULL ELSE 1 + t.ev % 2 END,
    t.tmin,
    t.tmax,
    t.cota,
    'ENEM',
    CASE WHEN t.cota LIKE 'Escola Pública%' THEN 'Pública'
         WHEN t.i % 2 = 0 THEN 'Privada'
         ELSE 'Pública' END,
    CASE WHEN t.i % 3 = 0 THEN (CASE WHEN t.i % 2 = 0 THEN 'Bolsa Permanência' ELSE 'Auxílio Moradia' END)
         ELSE 'Nenhum' END,                                 -- so quem tem renda "Até 1,5 SM" (i%3=0)
    t.blocado
FROM (
    SELECT b.*, date_part('year', age(DATE '2026-11-01', b.nasc))::int AS idade
    FROM (
        SELECT a.*,
               2023 + a.e / 2 AS y,
               1 + a.e % 2    AS s,
               (make_date(2023 + a.e / 2, CASE WHEN a.e % 2 = 0 THEN 3 ELSE 9 END, 1)
                   - ((17 + (a.i * 5) % 9) * 365 + (a.i * 53) % 365)) AS nasc,
               CASE WHEN a.i % 3 = 0 THEN
                        (CASE WHEN a.i % 2 = 0 THEN 'Escola Pública - Baixa Renda'
                              ELSE 'Escola Pública - Baixa Renda - PPI' END)
                    WHEN a.i % 4 IN (0, 1) THEN 'Escola Pública - Renda Superior'
                    ELSE 'Ampla Concorrência' END AS cota
        FROM tmp_aluno a
    ) b
) t
ORDER BY t.i;

-- 1.7 Fato_Aluno_em_Disciplina
--     Cada aluno cursa, a cada semestre desde o ingresso (ate a evasao, se houver),
--     as disciplinas do PROPRIO curso no periodo correspondente (semestre - ingresso + 1),
--     na turma ofertada naquele semestre.
CREATE TEMP TABLE tmp_matr AS
SELECT
    a.i                AS aluno_id,
    a.e,
    a.ev,
    m.m                AS sem,
    d.disciplina_id,
    d.fk_curso         AS curso_id,
    d.carga_horaria    AS ch,
    t.turma_id,
    -- data de referencia do semestre: 15/06 (1o sem) ou 15/12 (2o sem); id = posicao em dim_data
    (make_date(2023 + m.m / 2, CASE WHEN m.m % 2 = 0 THEN 6 ELSE 12 END, 15) - DATE '2023-01-01') + 1 AS tempo_id,
    a.hab,
    random() AS r1,
    random() AS r2,
    random() AS r3,
    random() AS r4
FROM tmp_aluno a
CROSS JOIN LATERAL generate_series(a.e, COALESCE(a.ev, 6)) AS m(m)
JOIN dm_aluno_prof.dim_disciplina d
  ON d.fk_curso = a.curso
 AND d.periodo  = LEAST(m.m - a.e + 1, a.duracao)
JOIN tmp_turma t
  ON t.disciplina_id = d.disciplina_id
 AND t.sem = m.m;

INSERT INTO dm_aluno_prof.fato_aluno_em_disciplina (
    tempo_id, turma_id, aluno_id, disciplina_id, curso_id,
    qtd_faltas, ch_adquirida, credito_adquirido, situacao, media_nota, e_bolsista
)
SELECT
    x.tempo_id,
    x.turma_id,
    x.aluno_id,
    x.disciplina_id,
    x.curso_id,
    x.faltas,
    CASE WHEN x.faltas <= x.ch * 0.25 AND x.nota >= 5.0 THEN x.ch      ELSE 0 END,
    CASE WHEN x.faltas <= x.ch * 0.25 AND x.nota >= 5.0 THEN x.ch / 15 ELSE 0 END,
    CASE WHEN x.faltas > x.ch * 0.25 THEN 'Reprovado por Falta'
         WHEN x.nota >= 5.0          THEN 'Aprovado'
         ELSE 'Reprovado por Nota' END,
    x.nota,
    (x.aluno_id % 3 = 0)                                    -- bolsista = tem assistencia estudantil
FROM (
    SELECT
        m.*,
        -- faltas: reprova por falta se > 25% da CH (alunos que evadem tendem a faltar muito no ultimo semestre)
        CASE WHEN (m.ev IS NOT NULL AND m.sem = m.ev) OR m.r4 < 0.06
             THEN FLOOR(m.ch * 0.25)::int + 1 + FLOOR(m.r2 * m.ch * 0.15)::int
             ELSE FLOOR(m.r2 * (m.ch * 0.20 + 1))::int
        END AS faltas,
        -- nota final (0 a 10), com componente do aluno + ruido
        ROUND(LEAST(10, GREATEST(0,
              10 * (0.5 * m.hab + 0.5 * (m.r1 + m.r3 + m.r2) / 3.0 + 0.22)))::numeric, 1) AS nota
    FROM tmp_matr m
) x
ORDER BY x.tempo_id, x.turma_id, x.aluno_id;

-- CH integralizada do aluno = soma real das cargas horarias aprovadas na fato
UPDATE dm_aluno_prof.dim_aluno da
   SET ch_integralizada = s.ch
  FROM (SELECT f.aluno_id, SUM(f.ch_adquirida)::int AS ch
          FROM dm_aluno_prof.fato_aluno_em_disciplina f
         GROUP BY f.aluno_id) s
  JOIN tmp_aluno ta ON ta.i = s.aluno_id
 WHERE da.numero_matricula = ta.matricula;


-- ============================================================================
-- 2. CARGA - SCHEMA: dm_prof (sincronizado)
-- ============================================================================

INSERT INTO dm_prof.dim_curso OVERRIDING SYSTEM VALUE SELECT * FROM dm_aluno_prof.dim_curso;
INSERT INTO dm_prof.dim_professor OVERRIDING SYSTEM VALUE SELECT * FROM dm_aluno_prof.dim_professor;
INSERT INTO dm_prof.dim_disciplina OVERRIDING SYSTEM VALUE SELECT * FROM dm_aluno_prof.dim_disciplina;
INSERT INTO dm_prof.dim_turma_disciplina OVERRIDING SYSTEM VALUE SELECT * FROM dm_aluno_prof.dim_turma_disciplina;
INSERT INTO dm_prof.dim_data (data_completa, semestre, ano, sem)
SELECT data_completa, semestre, ano, semestre FROM dm_aluno_prof.dim_data ORDER BY data_completa;

-- 2.6 Fato_Rend_Disciplina: uma linha consolidada por turma
--     (turma_disciplina_id recebe o id da disciplina, conforme a FK do DDL)
INSERT INTO dm_prof.fato_rend_disciplina (
    tempo_id, turma_id, turma_disciplina_id, curso_id,
    qtd_aprn, qtd_rprn, qtd_rprf, total_reprovados,
    menor_notas, maior_notas, mediana_notas, media_notas, media_faltas,
    qtd_notas_0_a_2_9, qtd_notas_3_a_6_9, qtd_notas_7_a_10,
    qtd_matriculados, prct_aprovados
)
SELECT
    tempo_id,
    turma_id,
    disciplina_id AS turma_disciplina_id,
    curso_id,
    COUNT(*) FILTER (WHERE situacao = 'Aprovado')            AS qtd_aprn,
    COUNT(*) FILTER (WHERE situacao = 'Reprovado por Nota')  AS qtd_rprn,
    COUNT(*) FILTER (WHERE situacao = 'Reprovado por Falta') AS qtd_rprf,
    COUNT(*) FILTER (WHERE situacao <> 'Aprovado')           AS total_reprovados,
    MIN(media_nota) AS menor_notas,
    MAX(media_nota) AS maior_notas,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY media_nota)::numeric, 2) AS mediana_notas,
    ROUND(AVG(media_nota)::numeric, 2) AS media_notas,
    ROUND(AVG(qtd_faltas)::numeric, 2) AS media_faltas,
    COUNT(*) FILTER (WHERE media_nota < 3.0)                         AS qtd_notas_0_a_2_9,
    COUNT(*) FILTER (WHERE media_nota >= 3.0 AND media_nota < 7.0)   AS qtd_notas_3_a_6_9,
    COUNT(*) FILTER (WHERE media_nota >= 7.0)                        AS qtd_notas_7_a_10,
    COUNT(*) AS qtd_matriculados,
    ROUND((COUNT(*) FILTER (WHERE situacao = 'Aprovado')::numeric / COUNT(*)::numeric) * 100, 2) AS prct_aprovados
FROM dm_aluno_prof.fato_aluno_em_disciplina
GROUP BY tempo_id, turma_id, disciplina_id, curso_id;


-- ============================================================================
-- 3. CONFERENCIAS (devem retornar 0 nas colunas "erros")
-- ============================================================================

-- 3.1 Contagens
SELECT 'dim_curso' AS tabela, COUNT(*) AS linhas FROM dm_aluno_prof.dim_curso
UNION ALL SELECT 'dim_professor',  COUNT(*) FROM dm_aluno_prof.dim_professor
UNION ALL SELECT 'dim_data',       COUNT(*) FROM dm_aluno_prof.dim_data
UNION ALL SELECT 'dim_disciplina', COUNT(*) FROM dm_aluno_prof.dim_disciplina
UNION ALL SELECT 'dim_turma',      COUNT(*) FROM dm_aluno_prof.dim_turma_disciplina
UNION ALL SELECT 'dim_aluno',      COUNT(*) FROM dm_aluno_prof.dim_aluno
UNION ALL SELECT 'fato_aluno_em_disciplina', COUNT(*) FROM dm_aluno_prof.fato_aluno_em_disciplina
UNION ALL SELECT 'fato_rend_disciplina',     COUNT(*) FROM dm_prof.fato_rend_disciplina;

-- 3.2 Aluno x disciplina do mesmo curso (erros deve ser 0)
SELECT COUNT(*) AS erros_curso_aluno_vs_disciplina
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN tmp_aluno a ON a.i = f.aluno_id
WHERE a.curso <> f.curso_id;

-- 3.3 Professor de campus diferente do campus do curso da turma (erros deve ser 0)
SELECT COUNT(*) AS erros_prof_outro_campus
FROM tmp_turma t
JOIN dm_aluno_prof.dim_turma_disciplina td ON td.codigo_turma =
     right((2023 + t.sem / 2)::text, 2) || (1 + t.sem % 2)::text || '-D' || LPAD(t.disciplina_id::text, 4, '0')
JOIN tmp_curso cc ON cc.seq = t.curso_id
JOIN tmp_curso cp ON cp.seq = 1 + (td.sk_p1 - 1) % (SELECT n_cursos FROM tmp_param)
WHERE cc.campi <> cp.campi OR cc.seq <> cp.seq;

-- 3.4 Aluno matriculado em semestre anterior ao ingresso (erros deve ser 0)
SELECT COUNT(*) AS erros_matricula_antes_do_ingresso
FROM tmp_matr WHERE sem < e;

-- 3.5 Situacao x faltas x nota (erros deve ser 0)
SELECT COUNT(*) AS erros_situacao
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN dm_aluno_prof.dim_disciplina d ON d.disciplina_id = f.disciplina_id
WHERE (f.situacao = 'Aprovado' AND (f.qtd_faltas > d.carga_horaria * 0.25 OR f.media_nota < 5))
   OR (f.situacao = 'Reprovado por Falta' AND f.qtd_faltas <= d.carga_horaria * 0.25)
   OR (f.situacao = 'Reprovado por Nota'  AND (f.qtd_faltas > d.carga_horaria * 0.25 OR f.media_nota >= 5));

-- 3.6 Taxa de aprovacao geral e por campus
SELECT c.campi,
       COUNT(*) AS matriculas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.situacao = 'Aprovado') / COUNT(*), 1) AS pct_aprovados
FROM dm_aluno_prof.fato_aluno_em_disciplina f
JOIN dm_aluno_prof.dim_curso c ON c.curso_id = f.curso_id
GROUP BY c.campi
ORDER BY c.campi;