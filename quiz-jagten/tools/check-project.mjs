import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const read = path => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const bank = JSON.parse(await read('questions.json'));
assert.ok(bank.length > 0, 'Danish question bank must not be empty');
const ids = new Set();
const errors = [];
let missingExplanations = 0;
for (const [index, q] of bank.entries()) {
  const label = `questions.json[${index}]`;
  if (!/^[a-z]{3}-\d{4}$/.test(q.id ?? '')) errors.push(`${label}: invalid id ${q.id}`);
  if (ids.has(q.id)) errors.push(`${label}: duplicate id ${q.id}`);
  ids.add(q.id);
  for (const field of ['kategori', 'niveau', 'status', 'type', 'spoergsmaal', 'korrekt', 'forkerte', 'forklaring']) {
    if (!(field in q)) errors.push(`${label}: missing field ${field}`);
  }
  if (typeof q.spoergsmaal !== 'string' || !q.spoergsmaal.trim()) errors.push(`${label}: empty question`);
  if (typeof q.korrekt !== 'string' || !q.korrekt.trim()) errors.push(`${label}: empty answer`);
  if (!Array.isArray(q.forkerte)) errors.push(`${label}: wrong answers must be an array`);
  if (q.type === 'mc' && (q.forkerte?.length !== 3 || new Set([q.korrekt, ...q.forkerte]).size !== 4)) errors.push(`${label}: MC question needs four distinct answers`);
  if (typeof q.forklaring !== 'string' || !q.forklaring.trim()) missingExplanations++;
}
assert.deepEqual(errors, [], errors.slice(0, 20).join('\n'));

const englishText = await read('questions.en.json').catch(() => null);
if (englishText) {
  const english = JSON.parse(englishText);
  assert.deepEqual(english.map(q => q.id), bank.map(q => q.id), 'English bank must preserve Danish IDs and order');
  for (const [index, q] of english.entries()) {
    for (const field of ['kategori', 'niveau', 'status', 'type']) assert.equal(q[field], bank[index][field], `questions.en.json[${index}].${field} must preserve metadata`);
    for (const field of ['spoergsmaal', 'korrekt', 'forklaring']) assert.equal(typeof q[field], 'string', `questions.en.json[${index}].${field} must be text`);
    assert.equal(q.forkerte?.length, bank[index].forkerte.length, `questions.en.json[${index}] must preserve answer count`);
  }
} else {
  console.warn('English bank is absent; the app will use Danish only.');
}

const app = await read('app.js');
for (const invariant of ['live-view-select', 'live-concept-select', "event: 'answer-ack'", 'player?.online', 'answers: revealedAnswers']) {
  assert.ok(app.includes(invariant), `Live-play invariant missing: ${invariant}`);
}
new vm.Script(app, { filename: 'quiz-jagten/app.js' });
const scoreboard = await read('scoreboard.html');
const scripts = [...scoreboard.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)];
assert.ok(scripts.length, 'scoreboard.html must include its canvas script');
for (const [index, match] of scripts.entries()) new vm.Script(match[1], { filename: `scoreboard.html inline script ${index + 1}` });

if (missingExplanations) console.warn(`${missingExplanations} Danish questions have an empty explanation; review before using explanation-heavy formats.`);
console.log(`Project checks passed: ${bank.length} Danish questions, ${ids.size} unique IDs, app and scoreboard syntax valid.`);
