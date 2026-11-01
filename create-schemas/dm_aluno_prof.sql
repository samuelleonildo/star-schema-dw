-- ============================================================================
-- 0. CRIAÇÃO DO SCHEMA dm_aluno_prof
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS dm_aluno_prof;

-- ============================================================================
-- 1. DIMENSÃO: DIM_Curso (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_curso (
    curso_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    departamento VARCHAR(200),
    centro VARCHAR(50),
    campi VARCHAR(50),
    duracao INTEGER,
    turno VARCHAR(50),
    modalidade_curso VARCHAR(50),
    modalidade_ensino VARCHAR(50),
    tempo_min_conclusao INTEGER,
    tempo_max_conclusao INTEGER,
    curriculo VARCHAR(50),
    carga_horaria INTEGER
);

-- ============================================================================
-- 2. DIMENSÃO: DIM_Professor (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_professor (
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
    estado_civil VARCHAR(30),
    deficiencia VARCHAR(50)
);

-- ============================================================================
-- 3. DIMENSÃO: DIM_Data (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_data (
    tempo_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data_completa DATE NOT NULL UNIQUE,
    semestre INTEGER NOT NULL,
    ano INTEGER NOT NULL,
    ano_semestre VARCHAR(10)
);

-- ============================================================================
-- 4. DIMENSÃO: DIM_Disciplina (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_disciplina (
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
        FOREIGN KEY (fk_curso) REFERENCES dm_aluno_prof.dim_curso (curso_id)
);

-- ============================================================================
-- 5. DIMENSÃO: DIM_TurmaDisciplina (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_turma_disciplina (
    turma_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_turma VARCHAR(50) NOT NULL,
    fk_disciplina INTEGER NOT NULL,
    sk_p1 INTEGER,
    sk_p2 INTEGER,
    sk_p3 INTEGER,
    CONSTRAINT fk_turma_disciplina 
        FOREIGN KEY (fk_disciplina) REFERENCES dm_aluno_prof.dim_disciplina (disciplina_id),
    CONSTRAINT fk_turma_prof1 
        FOREIGN KEY (sk_p1) REFERENCES dm_aluno_prof.dim_professor (professor_id),
    CONSTRAINT fk_turma_prof2 
        FOREIGN KEY (sk_p2) REFERENCES dm_aluno_prof.dim_professor (professor_id),
    CONSTRAINT fk_turma_prof3 
        FOREIGN KEY (sk_p3) REFERENCES dm_aluno_prof.dim_professor (professor_id)
);

-- ============================================================================
-- 6. DIMENSÃO: DIM_Aluno (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.dim_aluno (
    aluno_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_matricula VARCHAR(50) NOT NULL UNIQUE,
    nome VARCHAR(150) NOT NULL,
    data_nascimento DATE,
    faixa_etaria VARCHAR(20),
    genero VARCHAR(20),
    raca_etnia VARCHAR(30),
    faixa_economica VARCHAR(50),
    cpf VARCHAR(20) NOT NULL UNIQUE,
    curso_id INTEGER NOT NULL,
    nacionalidade VARCHAR(50),
    naturalidade VARCHAR(50),
    nome_mae VARCHAR(100),
    nome_pai VARCHAR(100),
    estado_civil VARCHAR(30),
    bairro_residencia VARCHAR(100),
    deficiencia VARCHAR(50),
    ano_conclusao_em INTEGER,
    semestre_ingresso INTEGER,
    ano_semestre_ingresso VARCHAR(10),
    ano_ingresso INTEGER,
    forma_ingresso VARCHAR(50),
    nivel_ensino VARCHAR(50),
    ch_integralizada INTEGER,
    tipo_evasao VARCHAR(50),
    ano_evasao INTEGER,
    semestre_evasao INTEGER,
    qtd_min_conc INTEGER,
    qtd_max_conc INTEGER,
    tipo_cota VARCHAR(50),
    meio_ingresso VARCHAR(50),
    tipo_escola_em VARCHAR(50),
    assistencia_estudantil VARCHAR(50),
    flg_blocado BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_aluno_curso 
        FOREIGN KEY (curso_id) REFERENCES dm_aluno_prof.dim_curso (curso_id)
);

-- ============================================================================
-- 7. TABELA FATO: Fato_Aluno_em_Disciplina (dm_aluno_prof)
-- ============================================================================
CREATE TABLE IF NOT EXISTS dm_aluno_prof.fato_aluno_em_disciplina (
    tempo_id INTEGER NOT NULL,
    turma_id INTEGER NOT NULL,
    aluno_id INTEGER NOT NULL,
    disciplina_id INTEGER NOT NULL,
    curso_id INTEGER NOT NULL,
    qtd_faltas INTEGER NOT NULL,
    ch_adquirida INTEGER NOT NULL,
    credito_adquirido INTEGER NOT NULL,
    situacao VARCHAR(30) NOT NULL,
    media_nota DECIMAL(4,2) NOT NULL,
    e_bolsista BOOLEAN NOT NULL,
    CONSTRAINT pk_fato_aluno_disciplina 
        PRIMARY KEY (tempo_id, turma_id, aluno_id, disciplina_id, curso_id),
    CONSTRAINT fk_fato_tempo 
        FOREIGN KEY (tempo_id) REFERENCES dm_aluno_prof.dim_data (tempo_id),
    CONSTRAINT fk_fato_turma 
        FOREIGN KEY (turma_id) REFERENCES dm_aluno_prof.dim_turma_disciplina (turma_id),
    CONSTRAINT fk_fato_aluno 
        FOREIGN KEY (aluno_id) REFERENCES dm_aluno_prof.dim_aluno (aluno_id),
    CONSTRAINT fk_fato_disciplina 
        FOREIGN KEY (disciplina_id) REFERENCES dm_aluno_prof.dim_disciplina (disciplina_id),
    CONSTRAINT fk_fato_curso 
        FOREIGN KEY (curso_id) REFERENCES dm_aluno_prof.dim_curso (curso_id)
);

-- ============================================================================
-- RETORNO PARA O METABASE
-- ============================================================================
SELECT 
    table_schema AS schema_criado,
    table_name AS tabela_criada
FROM information_schema.tables 
WHERE table_schema IN ('dm_prof', 'dm_aluno_prof')
ORDER BY table_schema, table_name;