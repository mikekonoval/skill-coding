# Spawn Recipes

Конкретные вызовы для каждого места в конвейере. Каждый рецепт начинается с проверки доступности.

---

## Рецепты для Claude Code (основной режим)

### Спавн агента-писателя (Claude-агент)

Используется для: писателя спеки, писателя плана, реализатора, фиксера.

**Claude Code (инструмент Task/Agent):**
```
description: "[роль] для [этапа роадмапа]"
prompt: |
  Прочитай SKILL.md по пути ниже ПЕРЕД началом работы.
  SKILL.md: [абсолютный путь к SKILL.md нужного скилла superpowers]

  [задача агента с полным контекстом]

  Рабочая директория: [путь к проекту]
```

Пути к SKILL.md superpowers скиллов (кэш плагина):
```bash
# Brainstorming (для писателя спеки)
~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/brainstorming/SKILL.md

# Writing plans (для писателя плана)
~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/writing-plans/SKILL.md

# Subagent-driven development (для реализатора)
~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/skills/subagent-driven-development/SKILL.md
```

Выбор модели: по рубрике → `model-routing.md`.

Пример передачи модели в подсказке (Claude Code не имеет флага --model для subagent, поэтому модель указывается в описании задачи для оркестратора, который задаёт её через поле `model` инструмента Agent):
```
model: claude-haiku-4-5    # ярус 1
model: claude-sonnet-4-6   # ярус 2
model: claude-fable-5      # ярус 3
```

**Правило:** заспавненный агент не наследует скиллы основной сессии. Без явной передачи пути к SKILL.md формат артефакта будет произвольным.

---

### Спавн Codex-ревьюера (`codex exec`)

Используется для: кросс-модельного ревьюера когда писатель — Claude-агент.

**Проверка доступности:**
```bash
command -v codex || { echo "ERROR: codex not found. Install: npm install -g @openai/codex"; exit 1; }
```

**Рецепт:**
```bash
# Записать промпт с заполненными плейсхолдерами во временный файл
cat > /tmp/review-prompt.txt << 'EOF'
[промпт из references/prompts/spec-review.md | plan-review.md | code-review.md
 с заполненными плейсхолдерами]
EOF

# Передать промпт через stdin (НЕ через аргумент или heredoc-подстановку)
codex exec -s read-only < /tmp/review-prompt.txt 2>&1
```

**Важно:** передавать промпт через `< /tmp/file` (stdin redirect), а не через `"$(cat << 'HEREDOC')"` — heredoc-подстановка в длинных промптах может зависнуть.

Флаги:
- `-s read-only` — обязательно: ревьюер читает репозиторий, но не изменяет его
- `-m <model>` — опционально: `codex exec -s read-only -m gpt-5.5 "..."` для конкретной модели
- По умолчанию: `gpt-5.5` (верхний ярус, правильно для ревью)

**Проверено локально:** codex-cli 0.137.0-alpha.4, рабочая директория `/Users/mikekonoval/Desktop/skill-coding`.

**Ожидаемый вывод:** текст с секциями Находки / Оценка по контракту из `review-protocol.md`.

**Ошибка транспорта vs. исчерпание лимитов** (разные ветки, не путать):
- **Лимиты codex исчерпаны** — ненулевой код выхода + вывод содержит `usage limit` / `rate limit` / `quota` / `429` / `too many requests`. Это **не** ошибка транспорта: автоматически перейти на opencode+DeepSeek (см. «Лестница ревьюера» ниже), волну **не** расходовать впустую.
- **Прочая ошибка** (пустой stdout, сетевой сбой, иной ненулевой код) → не считать как «ноль находок», применить правило честной деградации (см. ниже).

---

### Спавн opencode+DeepSeek-ревьюера (`opencode run`)

Используется как **fallback-ревьюер** когда писатель — Claude-агент, а codex недоступен/исчерпал лимиты. DeepSeek ≠ Claude → кросс-модельность сохраняется.

**Проверка доступности:**
```bash
command -v opencode || { echo "ERROR: opencode not found. Install: https://opencode.ai"; exit 1; }
opencode auth list 2>/dev/null | grep -qi deepseek || { echo "ERROR: DeepSeek не авторизован в opencode. Fix: opencode auth login → DeepSeek"; exit 1; }
```

**Рецепт:**
```bash
# Промпт — в том же /tmp-файле, что и для codex (тот же контракт находок)
opencode run --agent plan -m deepseek/deepseek-v4-pro < /tmp/review-prompt.txt 2>&1
```

Флаги:
- `--agent plan` — обязательно: встроенный read-only агент opencode (read без write/edit). Аналог `-s read-only` у codex — ревьюер не изменяет репозиторий.
- `-m deepseek/deepseek-v4-pro` — верхний ярус DeepSeek (правильно для ревью). Для спеки/плана допустим `deepseek/deepseek-reasoner`.
- Промпт через `< /tmp/file` (stdin), как у codex — без shell-подстановки длинного текста.

**Проверено локально:** opencode 1.15.10, DeepSeek API авторизован, агент `plan` read-only, рабочая директория `/Users/mikekonoval/Desktop/skill-coding`. Смоук-тест (`printf ... | opencode run --agent plan -m deepseek/deepseek-chat`) вернул ответ.

**Ожидаемый вывод:** строки `→ Read ...` (чтение файлов агентом) + текст находок по контракту из `review-protocol.md`. Парсить только секции находок, строки-логи чтения игнорировать.

---

### Лестница ревьюера (Claude Code-оркестратор)

Писатель — Claude-агент, значит ревьюер обязан быть не-Claude. Идти сверху вниз, остановиться на первом доступном:

1. **codex** (`codex exec -s read-only`) — основной кросс-модельный ревьюер.
2. **Лимиты codex исчерпаны?** (детектор выше: `usage limit`/`rate limit`/`quota`/`429`). → перейти к п.3, ту же волну продолжить на новом транспорте.
3. **opencode+DeepSeek** (`opencode run --agent plan -m deepseek/deepseek-v4-pro`) — fallback-ревьюер. DeepSeek ≠ Claude, кросс-модельность держится.
4. **Оба недоступны** → правило честной деградации (не подменять молча, сообщить пользователю, предложить альтернативы).

Важно: это лестница **транспорта одного ревьюера** в основном режиме, а не переключение в запасной режим целиком (тот — в `fallback-mode.md`, включается только по явному сигналу пользователя при исчерпании лимитов **Claude**).

---

### Спавн Claude-агента как ревьюера

Используется когда писатель — Codex-агент (ревьюер ≠ писатель).

```
description: "Кросс-модельный ревьюер [этапа]"
model: claude-fable-5
prompt: |
  [промпт из references/prompts/ с заполненными плейсхолдерами]
```

---

## Рецепты для Codex-оркестратора (запасной режим)

Подробнее → `fallback-mode.md`.

### Спавн Codex-агента-писателя

```python
# codex multi_agent = true, spawn_agent API
spawn_agent(
  role="writer",
  prompt="...",  # полный промпт с путём к SKILL.md
  model="gpt-4.1"  # ярус 2 по умолчанию для писателя
)
```

Пути к SKILL.md superpowers для Codex-оркестратора:
```bash
# Требует резолвинга ~/.agents/skills/superpowers/ (см. README)
~/.agents/skills/superpowers/skills/brainstorming/SKILL.md
~/.agents/skills/superpowers/skills/writing-plans/SKILL.md
~/.agents/skills/superpowers/skills/subagent-driven-development/SKILL.md
```

**Важно:** перед запуском Codex-оркестратора проверить:
```bash
ls ~/.agents/skills/superpowers/SKILL.md 2>/dev/null || {
  echo "ERROR: superpowers not found in ~/.agents/skills/"
  echo "Fix: ln -s ~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0 ~/.agents/skills/superpowers"
  exit 1
}
```

### Спавн DeepSeek-ревьюера

→ Два варианта в `fallback-mode.md`: deepcode CLI или DeepSeek API напрямую.

---

## Правило честной деградации

Если названный CLI недоступен:
1. Не подменять молча другим инструментом
2. Сообщить пользователю: «[инструмент] недоступен. Доступные альтернативы ревьюера: [список]»
3. Предложить:
   - Установить недостающий инструмент
   - Использовать Claude-агент другой модели как ревьюера (нарушает строгий cross-model, но лучше чем останов)
   - Продолжить с явным снижением гарантий кросс-модельности

**Пример для missing deepcode:**
```
deepcode не найден.
Доступные альтернативы ревьюера для запасного режима:
  1. DeepSeek API напрямую (требует ключ в ~/.deepcode/settings.json)
  2. codex exec (нарушает cross-model если оркестратор тоже на Codex)
Установить deepcode: npm install -g @vegamo/deepcode-cli
```

---

## API-ключи и секреты

**Никогда** не передавать API-ключи через флаги CLI — они видны в `ps aux` и логах терминала.

Правильно:
- DeepSeek ключ → `~/.deepcode/settings.json` (права 600)
- OpenAI ключ → `~/.codex/settings.json` или переменная окружения `OPENAI_API_KEY`

Проверка прав файла:
```bash
stat -f "%Lp" ~/.deepcode/settings.json  # должно быть 600
```
