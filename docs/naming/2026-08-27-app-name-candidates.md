# App name candidates (replacing "Dictato")

Date: 2026-08-27

## Decided: Nivi

**Chosen on 2026-08-27: the app is called Nivi**, said NEE-vee, from the Hebrew
*niv*, a turn of phrase. The bundle id is `com.dvir.nivi` and updates come from
`Dvirco1234/nivi`.

The rename landed the same day, before the first public release, because
changing a bundle id after release strands every install. See
[../release-pipeline.md](../release-pipeline.md) for what the rename touched and
how existing settings and models are carried over.

The rest of this page is the working document that led to the decision. It is
kept as it was written.

## The brief

Plain, calm, easy to remember, connected to the product. Not witty, not funny,
not clever. One or two syllables where possible. Obvious spelling. Works in a
menu bar, in a Dock tooltip, as `com.dvir.<name>`, and as a repo name.

Already rejected, plus close variants: Dictato, Kolmus, Tamlil, Ktav, KolFlow.
Lesson from the rejections: no Hebrew word in Latin letters that an English
speaker cannot say or spell, and no "Kol-something" compounds.

## Candidates

24 names, in four groups. React to the group first, then to the names.

### Group 1: plain English words about speech and writing

**1. Scribe**
A scribe writes down what is said. That is exactly the product.
Problem: very crowded. Scribe is already a big documentation tool and a common
name for transcription services. See the research section.

**2. Quill**
A writing tool. Short, calm, easy to spell.
Problem: Quill.js is a well known text editor library, so developers will think
of that first.

**3. Utter**
Plain English verb for saying something out loud. One clean idea: you utter, it
writes. Two syllables, spelling is obvious.
Problem: "utter" also means "complete", as in "utter nonsense". Mild, not fatal.

**4. Verbatim**
Word for word. That is the promise of a dictation app.
Pronounced ver-BAY-tim. Three syllables.
Problem: Verbatim is a large brand of USB drives and discs. Also a bit long.

**5. Aloud**
You speak aloud, the text appears. Simple, warm, and true.
Problem: people may hear "allowed". That is a real spelling trap when you say
the name in a call.

**6. Pen**
The oldest writing tool. Very short, impossible to misspell, sits well in a menu
bar.
Problem: extremely generic word, hard to own in search results.

**7. Prose**
The output of the app is prose. Calm, adult, slightly literary but still an
everyday word.
Pronounced "proze".
Problem: does not hint at voice at all.

### Group 2: plain English words about speed, quiet, and thinking out loud

**8. Murmur**
A low, quiet voice. Fits an app that listens quietly and runs on your machine.
Problem: Murmur is the name of the Mumble voice chat server. Developers know it.

**9. Hush**
Quiet and private in one short word. Fits the offline, nothing-leaves-your-Mac
story.
Problem: there is already a well known Hush app on Mac and iOS. See research.

**10. Draft**
Speaking is how you get a first draft out fast. Plain, serious, tool-like.
Problem: no link to voice, and Draft is used by many writing products.

**11. Ripple**
The waveform in the panel is a ripple. Sound moving through air.
Problem: Ripple is a large crypto company. Dead on arrival for search.

**12. Aside**
An aside is something you say out loud, briefly, on the side. It also matches
the small floating panel.
Problem: "aside" is a common HTML tag and a common word, so it is weak in
search. Slightly abstract.

**13. Tempo**
The speed of speech. Easy to say in Hebrew and English, easy to spell.
Problem: many products already use Tempo, including a Jira time tracker.

### Group 3: Hebrew-rooted, but easy for anyone

The bar here is high because of the earlier rejections. Each of these is a word
an English speaker can say correctly on the first try and spell after hearing it
once.

**14. Mila**
מילה, Hebrew for "word". Two syllables, MEE-la. Every English speaker can say it
and spell it. Meaningful in Hebrew, harmless and pleasant in English.
Problem: Mila is also a common girl's name and a home air purifier brand. Also
"MILA" is a well known AI research institute in Montreal.

**15. Sapir**
ספיר. Sounds like "sapphire" and shares the root with "sipur", a story, and
"safa", language. Pronounced sa-PEER.
Problem: some English speakers will say SAY-pir. Also Sapir is a common Israeli
first name and a college name.

**16. Safa**
שפה, Hebrew for "language". SAH-fah. Short and simple.
Problem: easy to misread as "sofa". Also a common name and a place name in
several countries.

**17. Shema**
שמע, "listen" or "hear". The app listens. SHEH-ma.
Problem: heavy religious weight in Hebrew, the name of a central prayer. That is
a lot to carry for a dictation app.

**18. Amar**
אמר, "he said". Two syllables, ah-MAR, no spelling doubt.
Problem: Amar is a common surname and brand name in several countries, and it
reads as a person's name more than a product.

### Group 4: short neutral words that just sound like a tool

**19. Onda**
"Wave" in Italian and Spanish. It matches the waveform you see while speaking.
ON-da. Two syllables, no spelling doubt.
Problem: Onda is a Chinese tablet and electronics brand.

**20. Vela**
A sail, and also a constellation. Calm, light, easy in both languages. VEH-la.
Problem: no link to speech. Several small startups use it.

**21. Rune**
An old written character. Short, hard, tool-like. Rhymes with "moon".
Problem: Rune is used by several dev tools and games. Slightly fantasy-flavoured.

**22. Aria**
A voice singing alone. Pretty and easy, AH-ree-a.
Problem: ARIA is the web accessibility standard, and Opera's AI assistant is
called Aria. Too much noise.

**23. Nomi**
Soft, neutral, two syllables, no baggage in Hebrew or English. NO-mee.
Problem: it means nothing, and Nomi is also an AI companion app.

**24. Solo**
One person, one machine, nothing sent anywhere. Fits the offline story.
Problem: very common word, and Han Solo owns the mental image.

## Availability research

Checked on 2026-08-27. Method: web search, App Store and Google Play listings,
GitHub search, and DNS lookups on domains. DNS only tells me if a domain is
registered, not if it is for sale or in real use. I could not run whois from
this machine, so treat domain notes as a strong hint, not proof.

First, the general finding, and it matters more than any single name. The Mac
dictation space is very crowded in 2026. Almost every plain English word for
speech or writing is already the name of a local dictation app, usually a small
one on GitHub or the App Store. Names with no direct speech meaning survive much
better.

### Killed during research

**Utter — dead.** utter.to is "Utter: AI Voice to Text for Mac & iPhone". There
is also "utter - Dictation, Voice Notes" on the App Store and "Utter: AI Voice
Keyboard" on Google Play. Same product, same name. No.

**Mila — dead.** github.com/island-io/mila is "Mila, native macOS local
transcription app (whisper.cpp)". That is this exact app. There is also
mila.rocks, a Mac meeting transcription app. This was my favourite before I
checked. It is gone.

**Murmur — dead.** At least five Mac voice products use it: murmurtype.com
(free offline dictation for Mac), murmur.you, usemurmur.com, murmurtts.com,
plus two GitHub projects and MurmurAI on the App Store. Completely burned.

**Scribe — dead.** ElevenLabs named their speech-to-text model Scribe. It is
the best known ASR brand name in the market right now. Also Scribe (scribehow)
in documentation. No chance.

**Quill — dead.** Three separate Mac dictation apps on GitHub use the name, plus
heyquill.ai ("the voice agent for Mac and iPhone") and iniyan.pro/quill, whose
tagline is "Speak, and it's typed, nothing leaves your Mac". That is literally
your pitch.

**Hush — dead.** "Hush Nag Blocker" is a famous free Safari blocker on Mac and
iOS. There is also "Hush | AI for Spoken Audio" on the Mac App Store.

**Aloud — effectively dead.** Google shipped a speech product called Aloud
(AI dubbing, from Area 120). Plus "read aloud" is a generic feature name, so
search is hopeless.

**Aside — dead.** heyaside.com is "Mac meeting notes that never join your call",
a transcription app. There is also a Mac scratchpad app called Aside.

**Verbatim — dead.** github.com/axtonliu/verbatim-flow is a macOS menu bar
dictation app that types into the focused app. "Verbatim AI" is on the App
Store. Verbatim is also a big storage media brand.

I also tested two names before adding them to the list, and both were already
taken by the same kind of product:
- **Sofer** (Hebrew for scribe): sofer.app is a Mac app that records and
  transcribes meetings locally. Its own line is "nothing leaves your device".
- **Tiro** (the Roman who invented shorthand): "Tiro, AI Meeting Notes" on the
  App Store and Google Play.

### Survivors, with findings

**Sapir** — the cleanest of the lot.
- No app called Sapir on the App Store. Nothing in Mac dictation or
  transcription. No notable software company.
- Non-software collisions: Sapir Organization (New York real estate), Sapir
  Venture Partners, Sapir Academic College in Israel.
- Domains: `sapir.app` is taken and in use by an Israeli parking system.
  `sapir.com` is taken. `sapir.dev` and `sapir.io` are taken. But
  `sapirapp.com`, `getsapir.com`, `usesapir.com` and `sapir.so` all had no DNS
  records, so they look free.
- GitHub: no major project owns the name.
- Meaning: sapphire in Hebrew. Nothing rude in Hebrew or English.
- Honest problem: in Israel, Sapir is a very common girl's name. Some Israelis
  will hear a person, not a product. Compare Alexa or Siri, this is survivable,
  but you should know it.

**Onda** — clean in this market, noisy elsewhere.
- No dictation or transcription app called Onda that I could find on the App
  Store.
- Real collision: ONDA Technologies, a Chinese electronics brand making tablets
  and motherboards since 1989. Different market, but it owns the search results.
- GitHub: several small projects named onda, including a Java audio compressor
  and a Julia signal package. None famous, but the name is not free.
- Domains: `onda.app` and `onda.com` are parked and for sale. `ondaapp.com`,
  `getonda.com` and `onda.dev` are all registered.
- Meaning: "wave" in Italian, Spanish and Portuguese. Nothing bad in Hebrew.

**Rune** — clean in dictation, but crypto noise.
- No Mac dictation or transcription app named Rune.
- Real problem: RUNE is a well known crypto token (THORChain), and "Runes" is a
  Bitcoin token standard from 2024. Searching "rune" gives crypto and RuneScape.
- There is also Rune Labs, a health data company.
- Domains: `rune.app`, `runeapp.com`, `rune.dev`, `getrune.com` are all
  registered, several parked for sale.
- Meaning: a written mark. Good link to the product. Nothing bad in Hebrew.

**Prose** — usable but weakened. There is a Mac App Store app called "Prose."
for writers. Not a dictation app, but the same shelf.

**Safa** — no dictation app found. "Safa Store" and "SAFA Mobile" exist on the
App Store, unrelated. Note that Safa is also a holy site in Islam (Mount Safa),
which some users will notice.

**Amar** — no dictation app, but ten or more unrelated apps named Amar on the
App Store, mostly Arabic and South Asian. Very crowded, weak to search.

**Vela** — no dictation app, but many small apps named Vela on the App Store
(travel, health, AI video). `vela.app` is taken.

**Pen, Draft, Solo, Nomi, Tempo, Ripple** — I did not run full checks, because
each has an obvious large collision already: Draft and Pen are too generic,
Ripple is a crypto company, Tempo is a Jira plugin, Nomi is an AI companion app,
Solo is Han Solo.

## Top 3

### 1. Sapir  (my recommendation)

Say it: sa-PEER.

Take it. It is the only name on the list where the field is genuinely empty. No
Mac app, no dictation product, no software company, no GitHub project. Every
plain English speech word is already burned by a small local dictation app, so a
clean name is worth a lot more than a clever one.

It is two syllables, spelled the way it sounds, and easy for an English speaker
on the first try. It is Hebrew without being a puzzle, which fits an app built
for Hebrew first. The link to the product is indirect: it shares a root feel
with safa (language) and sipur (story), and it means sapphire, something clear
and hard. I will not oversell that. The tie is soft. But a short clean name that
you can own beats a tight pun you have to share with five other apps.

Domain plan: `sapir.app` and `sapir.com` are gone. `getsapir.com`,
`sapirapp.com` and `usesapir.com` look free. Bundle id `com.dvir.sapir` is fine.
Known risk: it is a common Israeli first name.

### 2. Onda

Say it: ON-da. Wave.

The waveform in your panel is the product's face, so the name matches what the
user sees. Short, calm, easy in Hebrew and English, no dictation app owns it.
The cost is that a Chinese tablet brand owns the search results, and the
domains are parked. Good name, worse search position than Sapir.

### 3. Rune

Say it: roon. A written mark.

The best meaning of the three: your speech turns into written marks. One
syllable, no spelling doubt, sounds like a serious tool. No dictation app uses
it. It is third only because "rune" now means crypto to a large part of the
internet, and the domains are parked.

### What I would do

Go with **Sapir**. Buy `getsapir.com` or `sapirapp.com` today, take the GitHub
name, and move on. If the girl's-name issue bothers you when you say it out
loud a few times, go to **Onda**.

Do not spend another week on this. The main lesson from the research is that
the good speech words are all taken, so a short, clean, slightly abstract name
is the right call.

---

# Round 2

Dvir's reaction to round 1: "Mila sounds the better direction. Try to think
about similar things in a similar direction, but things that are not just one
word in Hebrew, but something that will somehow be easy to say and nice on the
ear."

So the target is the **sound**, not the meaning. Mila is two syllables, soft
consonants, open vowels, ends in "a". A Hebrew speaker and an English speaker
say it identically with no effort.

Rules for this round:
- Two syllables where possible, three at most. Soft consonants (m, l, n, s, v).
  Ends in "a" or "i". No guttural sounds, no consonant clusters.
- Not a plain dictionary Hebrew word. Bend a root, use a name or a place, or
  invent the word outright.
- Everything from round 1 still applies: no pun, no clever spelling, obvious to
  write down after hearing it once.

## Round 2 candidates

### Group A: shaped from a speech or writing root

**1. Nivi** (NEE-vee)
From "niv", a turn of phrase or an expression. Bent into a name shape, so it is
not the dictionary noun. Soft, short, very easy in both languages.
Problem: reads as a girl's name in Hebrew. Also close to "Nivea" for some ears.

**2. Amira** (ah-MEE-ra)
"Amira" is a saying or an utterance, and also a very common name in Hebrew and
Arabic. Beautiful sound, three syllables that flow.
Problem: it is still close to the dictionary word, and it is a widespread name.
Needs an availability check, see below.

**3. Sifra** (SIF-ra)
From the same root as sefer, a book, and sifrut, literature. Reads as a name.
Problem: has an "fr" cluster, which is slightly harder than Mila. Sifra is also
an old rabbinic text.

**4. Omera** (oh-MEH-ra)
Bent from "omer", he says. Soft, open, ends in "a".
Problem: sounds close to Omera the Japanese food brand and to "Omara". Weakest
link to anything, it just sounds nice.

**5. Amara** (ah-MAH-ra)
Same root as amar, said. Warm and Mediterranean.
Problem: Amara.org is a well known subtitling and captions platform. That is
close to the product. Likely dead, checked below.

**6. Tavi** (TAH-vee)
From "tav", a letter or a written mark. A name shape, not the noun.
Problem: Rikki-Tikki-Tavi. Also Tavi Gevinson. Small, but there.

### Group B: shaped from listening, calm and sound

**7. Nima** (NEE-ma)
From "ne'ima", a pleasant tune, shortened until it is its own word. Closest in
sound to Mila of anything here.
Problem: Nima is a common Persian male name.

**8. Noga** (NO-ga)
Venus, or a soft glow. A common Israeli name, not a product noun. Two syllables,
zero effort in either language.
Problem: Noga is the name of Israel's electricity system operator. Fine abroad,
known at home.

**9. Selah** (SEH-la)
An old word from the Psalms, a pause in the music. Hebrew-adjacent rather than
everyday Hebrew.
Problem: spelling wobble, people may write Sela. Strong religious flavour in
English-speaking Christian circles.

**10. Sheva** (SHEH-va)
The shva is the small vowel mark under a Hebrew letter, so there is a quiet link
to writing. Also "seven".
Problem: Israelis will hear "seven" or Beersheva first.

**11. Livna** (LIV-na)
A white tree, and a Hebrew name. Clean and calm.
Problem: three consonants in a row in the middle, "vn", which is slightly harsh
next to Mila.

### Group C: fully coined, no dictionary meaning

These should survive availability best, which matters a lot after round 1.

**12. Nela** (NEH-la)
Invented. Pure Mila shape, soft, warm, obvious spelling.
Problem: means nothing at all. Also a name in Slavic countries.

**13. Sila** (SEE-la)
Invented, though it exists as a Turkish name. Very close to Mila in the mouth.
Problem: "Sila" is also a fintech company and a battery company, see research.

**14. Vira** (VEE-ra)
Invented. Slightly firmer than Mila but still soft.
Problem: reads as "viral" or "virus" to some English speakers. That is a real
risk for a product name.

**15. Tela** (TEH-la)
Invented. Short, clean, tool-like, still soft.
Problem: "tela" is cloth in Spanish and Italian, and it looks like Tesla with a
letter missing. Second point is the serious one.

**16. Lavia** (la-VEE-a)
Invented, built on the sound of "lavi", a lion.
Problem: three syllables and slightly perfume-like.

### Group D: Hebrew names and places with the right sound

**17. Timna** (TIM-na)
A valley in the south of Israel, old copper mines. Not a product word at all.
Two syllables, unusual, easy to spell after hearing it.
Problem: "tm" then "n" makes it a touch harder than Mila. Timna is also a
biblical person.

**18. Arava** (ah-RAH-va)
The desert valley. Open, flowing, calm. Suits a quiet offline tool.
Problem: three syllables. Also an Israeli agriculture region brand.

**19. Alma** (AL-ma)
A common Hebrew name. Short, universal, easy everywhere.
Problem: crowded. Alma is a French payments company, an Israeli cyber training
centre, and "alma mater". Very hard to own.

**20. Lavi** (LA-vee)
A lion, and a kibbutz. Reads as a name, not a noun.
Problem: also a cancelled Israeli fighter jet, which older Israelis remember.

**21. Nira** (NEE-ra)
A Hebrew name. Soft, warm, exactly the Mila shape.
Problem: Nira is an existing SaaS company and a skincare device brand.

**22. Sivan** (see-VAHN)
A Hebrew month and a common name. Easy to say, easy to spell.
Problem: ends on a consonant, so it is a little flatter than Mila. Common name
in Israel.

## Round 2, side branch: can the "kol" root work?

You keep coming back to kol (קול, voice), so I gave the root a real try. The
design problem is simple to state. "Kol" is a hard K, a closed O and a final L.
An English mouth hears "coal". To get Mila's warmth you have to put a vowel
after the L and let the word keep flowing. Here is what that produces.

**K1. Kola** (KO-la)
Kol plus a soft ending. Dead immediately, it is Coca-Cola.

**K2. Koli** (KO-lee)
Two syllables, soft ending. Problem: an English reader sees "coli", as in
E. coli. That is fatal.

**K3. Kolia** (KOH-lee-a)
Softer, flows better. Problem: Kolya is a common Russian boy's name, and the
spelling wobbles between Kolia, Kolya and Kolja.

**K4. Kolina** (koh-LEE-na)
The L is now in the middle, so the "coal" sound is gone. Problem: it reads as a
girl's name, close to Colleen and Katarina, and "colina" is Spanish for hill.

**K5. Kolani** (koh-LAH-nee)
"Kolani" in Hebrew means vocal, so the root is real, and the word flows.
Problem: to English ears it is Hawaiian, right next to Kalani and Leilani. The
Hebrew is invisible.

**K6. Kolava** (koh-LAH-va)
Invented, keeps the root inside a flowing word. Problem: your ear finishes it as
lava, or baklava. It sounds like a dessert.

**K7. Kolev** (KO-lev)
A real Hebrew name, and it keeps the root sound. Problem: one letter from
"kelev", dog. Israelis will hear it. Also ends on a hard consonant.

**K8. Kolot** (ko-LOT)
Voices, the plural. Problem: it is the plain dictionary word you said you do not
want, and it ends hard.

**K9. Kalia** (KAH-lee-a)
A softer opening, and a real place in Israel. Problem: it drops the kol root
entirely. "Kal" is light or easy, not voice. So it is a nice sound with a false
story.

**K10. Vokal** (VO-kal)
Softens the opening and keeps the sound. Problem: it is "vocal" misspelled,
which breaks your rule about invented spellings. Also many products use it.

**K11. Qol** (kol)
The academic way to write the Hebrew letter. Problem: nobody knows how to say a
Q without a U. Spelling trap.

### My honest judgement on the kol branch

Do not use it. I tried the whole space and the root fails on its own terms.

Two problems, and they pull against each other. If you keep "kol" hard enough to
be recognisable, an English speaker says "coal" and the meaning is invisible to
everyone who does not already know Hebrew. If you soften it enough to sound like
Mila, it stops reading as kol at all and turns into a girl's name from somewhere
else, usually Russian or Hawaiian. Kolani is the best of them and it still lands
as Hawaiian.

Meaning that only works for people who already know the language is not doing
any work for you. Mila had the same property, and you liked Mila for the sound,
not the meaning. So take the sound and drop the root.

## Round 2 availability research

Checked on 2026-08-27, same method as round 1. Web search, App Store and Google
Play, GitHub, and DNS lookups. DNS tells me a domain is registered, not whether
it is for sale. I could not run whois from this machine.

### Killed in round 2

**Amira — dead.** Amira Learning is a funded edtech company whose product
listens to children read out loud using speech recognition. It has raised about
$40M and is used in schools across the United States. Speech AI, same space,
same name. Gone.

**Amara — dead.** Amara.org is a well known subtitling and captions platform.
Too close to what you do.

**Tela — dead.** Tella is a popular Mac screen recorder that captures screen,
camera and microphone. One letter apart, same kind of tool, same platform.

**Koli — dead.** English readers see E. coli. There is also a "KOLI" influencer
app.

**Omera — weak, effectively dead.** "Omera: AI Writing Keyboard" is on the App
Store. There is also Omera Software and an OMERA network tool. Writing keyboard
is close enough to your product to hurt.

**Sifra — weak.** Sifra AI on Google Play, Sifra Bank, and SifraDigital, a
Jerusalem app development firm. No dictation app, but noisy, and there is
already an Israeli software company using the name.

### Survivors, with findings

**Timna — the cleanest name in either round.**
- No app called Timna on the App Store or Google Play. Nothing in dictation,
  transcription or audio.
- No software company. The only tech reference is the Intel Timna, a processor
  cancelled in 2000 that almost nobody remembers.
- GitHub: nothing. Only a few personal accounts belonging to people named Timna.
- Domains: `timna.app`, `timna.dev`, `gettimna.com`, `timnaapp.com` and
  `usetimna.com` all had no DNS records, so they look unregistered. Only
  `timna.com` is taken.
- Meaning: a valley in the south of Israel with ancient copper mines. Also a
  biblical name. Nothing rude in Hebrew or English.
- Honest problem: it is a place and a person's name, so it says nothing about
  speech. And "TIM-na" is slightly harder in the mouth than Mila.

**Nivi — clean in this market, some business noise.**
- No dictation, transcription or audio app named Nivi.
- Several small companies: Nivi Software Solutions, NIVI Solutions, and Nivi, a
  digital health chatbot in emerging markets. None is famous.
- Domains: `nivi.app` and `nivi.com` are both registered.
- Meaning: from "niv", a turn of phrase. Closest thing here to a real link
  between sound and product.
- Honest problem: in Israel it reads as a girl's name.

**Nela — usable, generic.**
- No dictation app. NELA is a large German printing automation group, plus a
  language school app and a US employment lawyers' group.
- `nela.app` is parked and for sale.
- Means nothing anywhere, which is both the appeal and the weakness.

**Nima — usable but crowded.**
- No dictation app, but Nima was a well known consumer gluten sensor with a Mac
  and iOS app, and there are five or six unrelated Nima apps.
- `nima.app` is parked and for sale. Common Persian male name.

**Noga — weakened.**
- "NOGA Sound Solutions" is on the Mac App Store, an audio app. That is close to
  your space. There is also NOGA Software Limited in the UK and Noga, the
  Israeli electricity system operator.

**Sila — weakened.** Sila Money is a fintech payments platform, Sila HQ is a Y
Combinator team messaging app, and SiLA is a lab automation standard.

**Vira** — `vira.app` is parked for sale. More importantly, English speakers
hear "viral" or "virus". I would not ship it.

**Arava** — Arava is the brand name of a Sanofi arthritis drug. That is a strong
association and it is easy to find. Drop it.

**Alma, Nira, Lavi, Sivan, Selah, Sheva** — no dictation collisions, but all are
common names or common words with many small products already using them. Usable
if you love the sound, hard to own in search.

**Kolani and Kolina** — no direct software collision, but Kolina is a mobile
phone brand and Koloni is a sharing platform. This does not matter, because the
kol branch fails for the reasons above, not for availability.

## Round 2 top 3

### 1. Timna  (my recommendation)

Say it: TIM-na.

Take it. In two rounds of research this is the only name where everything is
free at once: no app, no company, no GitHub project, and the domains are
actually available. That is rare, and after round 1 you know how rare.

It has the shape you asked for. Two syllables, ends in "a", a Hebrew speaker and
an English speaker say it the same way, and nobody has to ask how it is spelled.
It is Israeli without being a translated product noun, which is exactly the
constraint you set. It is a place, an old quiet one, which suits a tool that runs
on your own machine and sends nothing anywhere.

I will be honest about the two weaknesses. It is a touch harder in the mouth than
Mila, because of the T and the "mn" in the middle. And it says nothing about
speech. You are buying a clean, ownable name, not a meaningful one.

Do this: `com.dvir.timna`, repo `timna`, buy `timna.app` and `gettimna.com`.

### 2. Nivi

Say it: NEE-vee.

The best sound of the three and the only one with a real link to the product.
"Niv" is a turn of phrase, and Nivi bends it into a name rather than using the
dictionary word. Soft, warm, effortless. Second because both good domains are
taken and there are several small companies using the name, and because in
Israel it reads as a girl's name first.

### 3. Nela

Say it: NEH-la.

Pure Mila shape, invented, no meaning to defend. No dictation app uses it. Third
because a large German industrial group owns NELA in search, and because a name
that means nothing gives you nothing to build a story on.

### What I would do

**Timna.** It is available everywhere, it fits the sound you asked for, and you
can own it. If the T bothers you when you say it out loud, go to **Nivi** and
accept the domain compromise, for example `getnivi.com`.

On kol: let it go. The root cannot be made soft and stay recognisable at the
same time. That is explained above.
