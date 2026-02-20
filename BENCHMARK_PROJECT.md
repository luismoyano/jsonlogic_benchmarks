# JSON Logic Ruby Benchmarks - Plan de Proyecto

*Fecha: 20 febrero 2026*

## Visión

Crear el sitio de referencia para benchmarks de implementaciones JSON Logic en Ruby, similar a como compat-tables es la referencia para compatibilidad. **Quien controla la medición, controla el relato.**

## Concepto

**Nombre**: `json-logic-ruby-benchmarks` (o `jsonlogic-benchmarks`)
**URL objetivo**: `benchmarks.jsonlogicruby.com` o similar
**Repositorio**: `github.com/luismoyano/json-logic-ruby-benchmarks`

## Diferenciadores vs compat-tables

| Aspecto | compat-tables | Nuestro benchmarks |
|---------|---------------|-------------------|
| Mide | Correctitud (pass/fail) | Performance (ops/sec) |
| Frecuencia | Manual/CI roto | **Semanal automatizado** |
| Transparencia | Código abierto | Código abierto + metodología documentada |
| Dimensiones | 1 (compatibilidad) | Múltiples (ver abajo) |

## Dimensiones a medir

1. **Throughput** - Operaciones por segundo
2. **Latencia** - Tiempo por operación (μs)
3. **Memory** - Uso de memoria por evaluación
4. **Versiones Ruby** - 2.7, 3.0, 3.1, 3.2, 3.3, 3.4, 4.0
5. **Categorías de operadores** - Comparaciones, lógicos, arrays, strings, matemáticos

## Gemas a incluir

| Gema | Notas |
|------|-------|
| shiny_json_logic | Nuestra gema |
| json-logic-rb | Kate (competidor activo) |
| json_logic | bhgames (abandonada pero rápida) |
| json_logic_ruby | Abandonada, referencia |

## Datos actuales (20 feb 2026)

### Benchmark con tests.json oficial (278 tests, 10 iteraciones)

#### Ruby 4.0.0
| Gema | Ops/sec | Time/op (μs) | vs Fastest |
|------|---------|--------------|------------|
| json_logic (bhgames) | 3,018,458 | 0.331 | FASTEST |
| **shiny_json_logic** | **328,372** | **3.045** | **10.9%** |
| json-logic-rb | 306,268 | 3.265 | 10.1% |

**shiny es 7.2% más rápido que Kate en Ruby 4.0**

#### Ruby 3.2.9
| Gema | Ops/sec | Time/op (μs) | vs Fastest |
|------|---------|--------------|------------|
| json_logic (bhgames) | 2,402,765 | 0.416 | FASTEST |
| json-logic-rb | 330,166 | 3.029 | 13.7% |
| **shiny_json_logic** | **279,649** | **3.576** | **11.6%** |

**Kate es 18% más rápida que shiny en Ruby 3.2**

#### Ruby 2.7.8
| Gema | Ops/sec | Time/op (μs) | vs Fastest |
|------|---------|--------------|------------|
| json_logic (bhgames) | 2,453,662 | 0.408 | FASTEST |
| **shiny_json_logic** | **102,488** | **9.757** | **4.2%** |
| json-logic-rb | N/A | N/A | Requiere Ruby 3.0+ |

**shiny es la ÚNICA opción activa para Ruby 2.7**

### Análisis de arquitectura

| Gema | Archivos .rb | Arquitectura | Compatibilidad |
|------|--------------|--------------|----------------|
| json_logic (bhgames) | 6 | Hash de lambdas | 63.9% |
| json-logic-rb | ~15 | Módulos | 99.67% |
| shiny_json_logic | 57 | OOP (clase por operador) | 99.7% |

**Conclusión**: json_logic es rápido porque es simple, pero incorrecto. Las gemas correctas (shiny y Kate) tienen overhead similar por diseño más robusto.

---

## Plan de ejecución

### Fase 1: MVP (1-2 días)

1. **Crear repositorio** `json-logic-ruby-benchmarks`
2. **Estructura básica**:
   ```
   json-logic-ruby-benchmarks/
   ├── README.md
   ├── benchmark/
   │   ├── runner.rb          # Script principal
   │   ├── gems.yml            # Configuración de gemas
   │   └── suites/
   │       └── official.json   # tests.json de jwadhams
   ├── results/
   │   └── YYYY-MM-DD/
   │       ├── ruby-2.7.8.json
   │       ├── ruby-3.2.x.json
   │       └── ruby-4.0.0.json
   ├── docs/
   │   └── methodology.md      # Metodología documentada
   └── .github/
       └── workflows/
           └── weekly.yml      # Cron semanal
   ```

3. **Script runner.rb** basado en `benchmark/performance_benchmark.rb` actual

### Fase 2: GitHub Actions (1 día)

1. **Matrix de Ruby versions**: 2.7, 3.0, 3.1, 3.2, 3.3, 3.4, 4.0
2. **Cron semanal**: Domingos a las 00:00 UTC
3. **Commit automático** de resultados a `results/`
4. **Badge dinámico** con último resultado

### Fase 3: Sitio web (2-3 días)

**Opción A**: GitHub Pages con Jekyll/Hugo
- Pros: Gratis, fácil
- Cons: Menos control de diseño

**Opción B**: Subdomain de jsonlogicruby.com (Rails)
- Pros: Consistencia de marca, control total
- Cons: Más trabajo

**Recomendación**: Empezar con GitHub Pages, migrar después si necesario.

1. **Página principal**: Tabla resumen con últimos resultados
2. **Histórico**: Gráficos de tendencia por gema/versión Ruby
3. **Metodología**: Página explicando cómo se mide
4. **Raw data**: Links a JSONs para que otros verifiquen

### Fase 4: Extras (backlog)

1. **Benchmarks por categoría de operador** (comparisons, logic, arrays, etc.)
2. **Memory benchmarks** con memory_profiler
3. **Flame graphs** para profiling visual
4. **Comparación con otras implementaciones** (JS, Python) - long-term

---

## Valor estratégico

### Control del relato

1. **Si shiny gana**: "El benchmark oficial muestra que somos los más rápidos"
2. **Si Kate gana**: "Felicidades a Kate, pero mira la tendencia/versiones Ruby/compatibilidad"
3. **Si alguien cuestiona**: "El código está abierto, la metodología documentada, corre tus propios benchmarks"

### Liderazgo técnico

- Otro aporte a la comunidad JSON Logic (después de var-falsy tests)
- Kate no puede "copiar" esto fácilmente - requiere infraestructura
- Refuerza narrativa de "shiny como proyecto serio"

### SEO

- Keywords: "json logic ruby benchmark", "json logic performance"
- Backlinks desde README de gemas, posts, etc.

---

## Cronograma propuesto

| Semana | Milestone |
|--------|-----------|
| Semana 1 | MVP: repo + runner + primeros resultados |
| Semana 2 | GitHub Actions funcionando |
| Semana 3 | Sitio web básico |
| Semana 4+ | Iteración basada en feedback |

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Kate optimiza y nos supera | El relato incluye múltiples dimensiones, no solo velocidad |
| Benchmarks inconsistentes | Documentar metodología, usar hardware consistente (GH Actions) |
| Nadie lo usa | Integrarlo en nuestra web, mencionar en posts, charla |
| Mantenimiento | GitHub Actions automatiza todo, mínimo esfuerzo |

---

## Código base disponible

El script actual está en:
- `benchmark/performance_benchmark.rb` - Runner completo
- `benchmark/data/tests.json` - Suite oficial
- `benchmark/results_ruby_*.json` - Resultados de hoy

Este código puede adaptarse directamente para el nuevo proyecto.
