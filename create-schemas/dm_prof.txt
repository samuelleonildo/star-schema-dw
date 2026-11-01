-- ============================================================================
-- 0. CRIAÇÃO DO SCHEMA dm_prof
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS dm_prof;

-- ============================================================================
-- 1. DIMENSÃO: DIM_Curso (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.dim_curso (
    curso_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    departamento VARCHAR(200),
    centro VARCHAR(50),
    campi VARCHAR(200),
    duracao INTEGER,
    turno VARCHAR(50),
    modalidade_curso VARCHAR(50),
    modalidade_ensino VARCHAR(50),
    tempo_min_conclusao VARCHAR(10),
    tempo_max_conclusao VARCHAR(10),
    curriculo VARCHAR(50),
    carga_horaria INTEGER
);

-- ============================================================================
-- 2. DIMENSÃO: DIM_Professor (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.dim_professor (
    professor_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_matricula VARCHAR(50) NOT NULL UNIQUE,
    nome VARCHAR(150) NOT NULL,
    data_nascimento DATE,
    faixa_etaria VARCHAR(20),
    genero VARCHAR(20),
    raca_etnia VARCHAR(30),
    bairro_residencia VARCHAR(100),
    cpf VARCHAR(20) NOT NULL UNIQUE,
    nacionalidade VARCHAR(50),
    naturalidade VARCHAR(50),
    nome_mae VARCHAR(100),
    nome_pai VARCHAR(100),
    estado_civil VARCHAR(50),
    deficiencia VARCHAR(50)
);

-- ============================================================================
-- 3. DIMENSÃO: DIM_Data (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.dim_data (
    tempo_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data_completa DATE NOT NULL UNIQUE,
    semestre INTEGER NOT NULL,
    ano INTEGER NOT NULL,
    sem INTEGER
);

-- ============================================================================
-- 4. DIMENSÃO: DIM_Disciplina (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.dim_disciplina (
    disciplina_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_disciplina VARCHAR(20) NOT NULL UNIQUE,
    nome VARCHAR(100) NOT NULL,
    carga_horaria INTEGER NOT NULL,
    creditos INTEGER,
    periodo INTEGER,
    fk_curso INTEGER,
    tipo VARCHAR(50),
    horario VARCHAR(100),
    CONSTRAINT fk_disciplina_curso 
        FOREIGN KEY (fk_curso) REFERENCES dm_prof.dim_curso (curso_id)
);

-- ============================================================================
-- 5. DIMENSÃO: DIM_TurmaDisciplina (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.dim_turma_disciplina (
    turma_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_turma VARCHAR(50) NOT NULL,
    fk_disciplina INTEGER NOT NULL,
    sk_p1 INTEGER,
    sk_p2 INTEGER,
    sk_p3 INTEGER,
    CONSTRAINT fk_turma_disciplina 
        FOREIGN KEY (fk_disciplina) REFERENCES dm_prof.dim_disciplina (disciplina_id),
    CONSTRAINT fk_turma_prof1 
        FOREIGN KEY (sk_p1) REFERENCES dm_prof.dim_professor (professor_id),
    CONSTRAINT fk_turma_prof2 
        FOREIGN KEY (sk_p2) REFERENCES dm_prof.dim_professor (professor_id),
    CONSTRAINT fk_turma_prof3 
        FOREIGN KEY (sk_p3) REFERENCES dm_prof.dim_professor (professor_id)
);

-- ============================================================================
-- 6. TABELA FATO: Fato_Rend_Disciplina (dm_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_prof.fato_rend_disciplina (
    tempo_id INTEGER NOT NULL,
    turma_id INTEGER NOT NULL,
    turma_disciplina_id INTEGER NOT NULL,
    curso_id INTEGER NOT NULL,
    qtd_aprn INTEGER NOT NULL,
    qtd_rprn INTEGER NOT NULL,
    qtd_rprf INTEGER NOT NULL,
    total_reprovados INTEGER NOT NULL,
    menor_notas DECIMAL(4,2) NOT NULL,
    maior_notas DECIMAL(4,2) NOT NULL,
    mediana_notas DECIMAL(4,2) NOT NULL,
    media_notas DECIMAL(4,2) NOT NULL,
    media_faltas DECIMAL(5,2) NOT NULL,
    qtd_notas_0_a_2_9 INTEGER NOT NULL,
    qtd_notas_3_a_6_9 INTEGER NOT NULL,
    qtd_notas_7_a_10 INTEGER NOT NULL,
    qtd_matriculados INTEGER NOT NULL,
    prct_aprovados DECIMAL(5,2) NOT NULL,
    CONSTRAINT pk_fato_rend_disciplina 
        PRIMARY KEY (tempo_id, turma_id, turma_disciplina_id, curso_id),
    CONSTRAINT fk_fato_rend_tempo 
        FOREIGN KEY (tempo_id) REFERENCES dm_prof.dim_data (tempo_id),
    CONSTRAINT fk_fato_rend_turma 
        FOREIGN KEY (turma_id) REFERENCES dm_prof.dim_turma_disciplina (turma_id),
    CONSTRAINT fk_fato_rend_disciplina 
        FOREIGN KEY (turma_disciplina_id) REFERENCES dm_prof.dim_disciplina (disciplina_id),
    CONSTRAINT fk_fato_rend_curso 
        FOREIGN KEY (curso_id) REFERENCES dm_prof.dim_curso (curso_id)
);

-- ============================================================================
-- RETORNO PARA O METABASE (Verifica as tabelas criadas no schema dm_prof)
-- ============================================================================
SELECT 
    table_schema AS schema_dm,
    table_name AS tabela_criada
FROM information_schema.tables 
WHERE table_schema = 'dm_prof'
ORDER BY table_name;