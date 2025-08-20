<script lang="ts">
	import Asm6502Editor from '$lib/components/Asm6502Editor.svelte';
	import MemoryViewer from '$lib/components/MemoryViewer.svelte';
	import GodotEngine from '$lib/components/GodotEngine.svelte';
	import FrequencySlider from '$lib/components/FrequencySlider.svelte';
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';

	// Svelte 5 runes (state + effects)
	let activeTab = $state('tab1');
	let isRespawning = $state(false);
	let godotEngineComponent: GodotEngine;

	const TAB_KEY = 'retro.activeTab';

	let engine: any = null;

	// Persist/restore active tab
	onMount(() => {
		try {
			const saved = localStorage.getItem(TAB_KEY);
			if (saved) activeTab = saved;
		} catch {}
	});

	// Handle engine ready callback
	function handleEngineReady(engineInstance: any) {
		engine = engineInstance;
		console.log('Engine ready in main component');
	}

	async function handleRespawnShip() {
		if (isRespawning) return;

		try {
			isRespawning = true;
			console.log('Respawning ship with code:', source);
			await WebHelper.respawnShipWithCode(source);
			console.log('Ship respawned successfully!');
		} catch (error) {
			console.error('Failed to respawn ship:', error);
		} finally {
			isRespawning = false;
		}
	}

	$effect(() => {
		try {
			localStorage.setItem(TAB_KEY, activeTab);
		} catch {}
	});

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

	let source = $state(`THRUSTER_1 = $020C
FIRE_UP = 8
FIRE_DOWN = 4

.org $0600

main_loop:
	LDA #FIRE_UP
	STA THRUSTER_1
	JSR delay
	
	LDA #0
	STA THRUSTER_1
	JSR delay

	LDA #FIRE_DOWN
	STA THRUSTER_1
	JSR delay

	LDA #0
	STA THRUSTER_1
	JSR delay

	JMP main_loop

delay:
	LDX #5
inner_loop:
	NOP
	DEX
	BNE inner_loop
	RTS
	`);


</script>

<svelte:head>
	<script src="/SpessComputer.js"></script>
	<link id="-gd-engine-icon" rel="icon" type="image/png" href="SpessComputer.icon.png" />
	<link rel="apple-touch-icon" href="SpessComputer.apple-touch-icon.png" />
	<link rel="manifest" href="SpessComputer.manifest.json" />
</svelte:head>

<main class="grid gap-4 p-4 lg:grid-cols-[2fr_1fr]">
	<!-- LEFT: Canvas panel -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)]">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>VISUAL LINK</span>
		</div>
		<div
			class="bg-[#131318] shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			<GodotEngine bind:this={godotEngineComponent} onEngineReady={handleEngineReady} />
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
		</div>

		<!-- Panels -->
		<div
			class="h-[calc(60vh-6rem)] bg-[#131318] p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_0_1px_rgba(255,184,107,0.08)] lg:h-[calc(78vh-6rem)]"
		>
			{#if activeTab === 'tab1'}
				<div
					id="tab-panel-1"
					role="tabpanel"
					aria-labelledby="tab1"
					aria-hidden="false"
					class="flex h-full flex-col gap-3"
					in:fade={{ duration: 150 }}
				>
					<div class="flex-1">
						<Asm6502Editor bind:value={source} className="h-full" />
					</div>
						<button
						onclick={() => handleRespawnShip()}
						class="transform border border-[#ffb86b]/40 bg-[#0f0f12] px-4 py-2 tracking-[0.18em]
						       text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] transition hover:text-[#ffb86b]
						       hover:brightness-110 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50"
							disabled={isRespawning}
						type="button"
						>
						{isRespawning ? 'RESPAWNING...' : 'RESPAWN SHIP WITH CODE'}
						</button>
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
					class="flex h-full flex-col"
					in:fade={{ duration: 150 }}
				>
					{#if engine}
						<div class="min-h-0 flex-1">
							<MemoryViewer />
						</div>
						<div class="mt-3">
							<FrequencySlider />
						</div>
					{/if}
				</div>
			{:else}
				<div
					id="tab-panel-2"
					role="tabpanel"
					aria-labelledby="tab2"
					aria-hidden="true"
					hidden
				>
					{#if engine}
						<div class="min-h-0 flex-1" style="display: none;">
							<MemoryViewer />
						</div>
						<div class="mt-3" style="display: none;">
							<FrequencySlider />
						</div>
					{/if}
				</div>
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
