# Fallback Mode: Codex-оркестратор + DeepSeek-ревьюер

Запасной режим включается когда лимиты Claude исчерпаны.

---

## Когда включать

Пользователь явно сообщает: «лимиты Claude исчерпаны», «switch to fallback», «используй Codex».

Оркестратор НЕ переключается автоматически — только по явному сигналу.

---

## Что меняется

| | Основной режим | Запасной режим |
|--|---|---|
| Оркестратор | Claude Code (Fable 5) | Codex (gpt-5.5) |
| Писатели (спека/план/код/**документация**) | Claude-агенты | Codex spawn_agent |
| Ревьюер спеки/плана | `codex exec -s read-only` | DeepSeek ревьюер |
| Ревьюер кода | `codex exec -s read-only` | DeepSeek ревьюер |
| Ревьюер документации | `codex exec -s read-only` | DeepSeek ревьюер |
| Фиксер | Claude-агент | Codex spawn_agent |

## Что остаётся прежним

- Конвейер: roadmap → spec → plan → impl → code review → **docs** (Фаза E — все пять фаз)
- Гейты волн ревью (критерий остановки, кап, DISPUTED)
- Контракт находок (Critical/Important/Minor)
- Правило «оркестратор не пишет содержимое артефактов»
- Рубрика маршрутизации моделей (ярусы → ярусы Codex)

---

## Пре-флайт для Codex-оркестратора

```bash
# 1. codex доступен
command -v codex || { echo "ERROR: codex not found"; exit 1; }

# 2. superpowers резолвится через ~/.agents/skills/
ls ~/.agents/skills/superpowers/SKILL.md 2>/dev/null || {
  echo "ERROR: superpowers not in ~/.agents/skills/"
  echo "Fix: ln -s ~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0 ~/.agents/skills/superpowers"
  exit 1
}

# 3. DeepSeek ревьюер — один из двух вариантов:
#    Вариант A: deepcode CLI
command -v deepcode && echo "deepcode: OK" || echo "deepcode: not found (нужен вариант B)"

#    Вариант B: DeepSeek API напрямую
[ -f ~/.deepcode/settings.json ] && \
  python3 -c "import json; d=json.load(open('$HOME/.deepcode/settings.json')); print('api_key:', 'present' if d.get('api_key') else 'MISSING')" || \
  echo "~/.deepcode/settings.json: not found"
```

---

## DeepSeek-ревьюер: Вариант A — deepcode CLI

**Статус (2026-06-11):** deepcode 0.1.29 установлен. Headless-поведение не проверено — документировано только как «TUI с предзаполненным промптом». Протестировать как только API-ключ будет настроен.

```bash
# Попытка headless
deepcode -p "$(cat <<'PROMPT'
[промпт из references/prompts/ с заполненными плейсхолдерами]
PROMPT
)" 2>&1

# Если не работает без TTY — использовать вариант B
```

Ожидаемый признак headless-работы: вывод без интерактивного UI в piped stdout.

---

## DeepSeek-ревьюер: Вариант B — DeepSeek API напрямую

Если `deepcode -p` требует TTY — вызывать DeepSeek chat-completions API с диффом в payload.

**Настройка ключа:**
```bash
# ~/.deepcode/settings.json (создать, права 600)
{
  "api_key": "sk-..."
}
chmod 600 ~/.deepcode/settings.json
```

**Рецепт вызова API:**
```bash
DEEPSEEK_KEY=$(python3 -c "import json; print(json.load(open('$HOME/.deepcode/settings.json'))['api_key'])")

curl -s https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DEEPSEEK_KEY" \
  -d "$(python3 -c "
import json, sys
prompt = open('/dev/stdin').read()
print(json.dumps({
  'model': 'deepseek-reasoner',
  'messages': [{'role': 'user', 'content': prompt}],
  'stream': False
}))
" <<'PROMPT'
[промпт из references/prompts/ с заполненными плейсхолдерами]
PROMPT
)" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
```

**Модели DeepSeek для ревью:**
- `deepseek-reasoner` — для ревью кода (сильнее в reasoning)
- `deepseek-chat` — для ревью спеки/плана (быстрее)

---

## DeepSeek-ревьюер: Вариант C — opencode (рекомендуемый, проверен)

Самый чистый headless-транспорт DeepSeek: ключ уже в opencode, есть read-only агент `plan`, промпт через stdin. Полный рецепт и проверка доступности — в `spawn-recipes.md` («Спавн opencode+DeepSeek-ревьюера»).

```bash
opencode run --agent plan -m deepseek/deepseek-v4-pro < /tmp/review-prompt.txt 2>&1
```

В отличие от A/B не требует отдельной настройки `~/.deepcode/settings.json` — авторизация DeepSeek живёт в opencode (`opencode auth list`).

---

## Статус DeepSeek-верификации

**Вариант C (opencode + DeepSeek) проверен 2026-06-14:** opencode 1.15.10, DeepSeek API авторизован, `deepseek-v4-pro` через агент `plan` (read-only) возвращает находки по контракту. Это рабочий путь по умолчанию.

Варианты A (deepcode CLI) и B (DeepSeek API напрямую) на 2026-06-11 ещё не проверены headless — именованный follow-up:

> **Follow-up: DeepSeek smoke test (A/B)**
> Условие запуска: нужен headless deepcode или прямой API вместо opencode
> Действие: запустить рецепт вар. B с игрушечным диффом (1-2 строки), убедиться что возвращаются находки в формате контракта.
> После проверки: обновить этот файл — отметить какой вариант (A или B) работает headless.

---

## Переключение обратно

Как только лимиты Claude восстановлены — явно сообщить оркестратору «вернись в основной режим». Конвейер продолжается с того гейта, где был остановлен (resume по роадмапу).
