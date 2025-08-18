<script lang="ts">
	import Asm6502Editor from '$lib/components/Asm6502Editor.svelte';
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';

	// Svelte 5 runes (state + effects)
	let activeTab = $state('tab1');
	let canvasEl: HTMLCanvasElement; // <canvas>
	let wrapEl: HTMLDivElement; // canvas container

	const TAB_KEY = 'retro.activeTab';

	// Persist/restore active tab
	onMount(() => {
		try {
			const saved = localStorage.getItem(TAB_KEY);
			if (saved) activeTab = saved;
		} catch {}

		// Initial paint once (no repaint on resize per user request)
		paintOnce();
	});
	$effect(() => {
		try {
			localStorage.setItem(TAB_KEY, activeTab);
		} catch {}
	});

	function paintOnce() {
		if (!canvasEl || !wrapEl) return;
		const rect = wrapEl.getBoundingClientRect();
		const dpr = window.devicePixelRatio || 1;
		canvasEl.width = Math.max(1, Math.floor(rect.width * dpr));
		canvasEl.height = Math.max(1, Math.floor(rect.height * dpr));
		const ctx = canvasEl.getContext('2d');
		if (!ctx) return;
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		ctx.fillStyle = '#1f1f1f';
		ctx.fillRect(0, 0, rect.width, rect.height);
	}

	function onTabsKey(e: KeyboardEvent) {
		const ids = ['tab1', 'tab2', 'tab3'];
		const i = ids.indexOf(activeTab);
		if (e.key === 'ArrowRight') {
			activeTab = ids[(i + 1) % ids.length];
			e.preventDefault();
		}
		if (e.key === 'ArrowLeft') {
			activeTab = ids[(i - 1 + ids.length) % ids.length];
			e.preventDefault();
		}
		if (e.key === 'Home') {
			activeTab = ids[0];
			e.preventDefault();
		}
		if (e.key === 'End') {
			activeTab = ids[ids.length - 1];
			e.preventDefault();
		}
	}

  let source = $state(`THRUSTER_ZERO = $020D

.org $0600

main_loop:
	LDA #8
	STA THRUSTER_ZERO
	JSR delay
	
	LDA #0
	STA THRUSTER_ZERO
	JSR delay

	LDA #4
	STA THRUSTER_ZERO
	JSR delay

	LDA #0
	STA THRUSTER_ZERO
	JSR delay

	JMP main_loop

delay:
	LDX #10
outer_loop:
	LDY #$FF
inner_loop:
	NOP
	DEY
	BNE inner_loop
	DEX
	BNE outer_loop
	RTS
`);
</script>

<main class="grid gap-4 p-4 lg:grid-cols-[2fr_1fr]">
	<!-- LEFT: Canvas panel -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)]">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>VISUAL LINK</span>
		</div>
		<div
			class="bg-[#131318] p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			<div class="relative h-[60vh] lg:h-[78vh]" bind:this={wrapEl}>
				<canvas class="absolute inset-0 h-full w-full" bind:this={canvasEl} aria-label="main canvas"
				></canvas>
			</div>
		</div>
		<!-- Corners -->
		{@render Corner('tl')}
		{@render Corner('tr')}
		{@render Corner('bl')}
		{@render Corner('br')}
	</section>

	<!-- RIGHT: Tabs panel -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)]">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>CONTROL DECK</span>
		</div>

		<!-- Tabs -->
		<div
			class="flex gap-2 border-b border-[#ffb86b]/20 bg-[#0f0f12] px-3 py-2"
			role="tablist"
			aria-label="Controls"
			onkeydown={onTabsKey}
			tabindex="0"
		>
			{@render Tab('tab1', 'Code Editor')}
			{@render Tab('tab2', 'Memory Viewer')}
			{@render Tab('tab3', 'Manual')}
		</div>

		<!-- Panels -->
		<div
			class="h-[calc(60vh-6rem)] lg:h-[calc(78vh-6rem)] bg-[#131318] p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			{#if activeTab === 'tab1'}
				<div
					id="tab-panel-1"
					role="tabpanel"
					aria-labelledby="tab1"
					aria-hidden="false"
					class="h-full"
					in:fade={{ duration: 150 }}
				>
        <Asm6502Editor bind:value={source} className="h-full"/>
      </div>
			{:else}
				<div id="tab-panel-1" role="tabpanel" aria-labelledby="tab1" aria-hidden="true" hidden>
					<!-- hidden -->
				</div>
			{/if}

			{#if activeTab === 'tab2'}
				<div
					id="tab-panel-2"
					role="tabpanel"
					aria-labelledby="tab2"
					aria-hidden="false"
					in:fade={{ duration: 150 }}
				>
					{@render PlaceholderElement('BRAVO')}
          {source}
				</div>
			{:else}
				<div
					id="tab-panel-2"
					role="tabpanel"
					aria-labelledby="tab2"
					aria-hidden="true"
					hidden
				></div>
			{/if}

			{#if activeTab === 'tab3'}
				<div
					id="tab-panel-3"
					role="tabpanel"
					aria-labelledby="tab3"
					aria-hidden="false"
					in:fade={{ duration: 150 }}
				>
					{@render PlaceholderElement('CHARLIE')}
				</div>
			{:else}
				<div
					id="tab-panel-3"
					role="tabpanel"
					aria-labelledby="tab3"
					aria-hidden="true"
					hidden
				></div>
			{/if}
		</div>
		{@render Corner('tl')}
		{@render Corner('tr')}
		{@render Corner('bl')}
		{@render Corner('br')}
	</section>
</main>

<!-- Corner component -->

{#snippet Corner(position: string)}
	<div
		class={'corner pointer-events-none absolute ' + position}
		class:tl={position === 'tl'}
		class:tr={position === 'tr'}
		class:br={position === 'br'}
		class:bl={position === 'bl'}
	>
		<span class="h absolute h-[2px] w-6 bg-[#ffb86b]"></span>
		<span class="v absolute h-6 w-[2px] bg-[#ffb86b]"></span>
	</div>
{/snippet}

<!-- Tab component -->
{#snippet Tab(id: string, label: string)}
	<button
		role="tab"
		aria-selected={activeTab === id}
		aria-controls={`tab-panel-${id.slice(-1)}`}
		tabindex={activeTab === id ? 0 : -1}
		onclick={() => (activeTab = id)}
		class="transform border border-[#ffb86b]/40 bg-[#0f0f12] px-3 py-2 tracking-[0.18em]
           text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] transition hover:brightness-110
           active:scale-[0.98] data-[active=true]:text-[#ffb86b]"
		data-active={activeTab === id}
	>
		{label}
	</button>
{/snippet}

<!-- Placeholder panel content -->
{#snippet PlaceholderElement(section: string)}
	<div class="grid gap-2 text-sm">
		<div
			class="flex items-center justify-between border border-[#ffb86b]/35 px-2 py-1 text-[11px] tracking-[0.25em]"
		>
			<span>SECTION</span><span>{section}</span>
		</div>
		<div class="h-24 bg-[#0f0f12] shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15)]"></div>
		<div class="h-8 bg-[#0f0f12] shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15)]"></div>
	</div>
{/snippet}

<style>
	@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap');
	/* Corner orientations (utility-friendly) */
	.corner.tl {
		top: 0;
		left: 0;
	}
	.corner.tr {
		top: 0;
		right: 0;
	}
	.corner.br {
		bottom: 0;
		right: 0;
	}
	.corner.bl {
		bottom: 0;
		left: 0;
	}

	.corner .h {
		width: 24px;
		height: 2px;
		position: absolute;
	}
	.corner .v {
		width: 2px;
		height: 24px;
		position: absolute;
	}

	.corner.tl .h {
		top: 0;
		left: 0;
	}
	.corner.tl .v {
		top: 0;
		left: 0;
	}

	.corner.tr .h {
		top: 0;
		right: 0;
	}
	.corner.tr .v {
		top: 0;
		right: 0;
	}

	.corner.br .h {
		bottom: 0;
		right: 0;
	}
	.corner.br .v {
		bottom: 0;
		right: 0;
	}

	.corner.bl .h {
		bottom: 0;
		left: 0;
	}
	.corner.bl .v {
		bottom: 0;
		left: 0;
	}
</style>
