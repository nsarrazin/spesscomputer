<script lang="ts">
	import Asm6502Editor from '$lib/components/Asm6502Editor.svelte';
	import MemoryViewer from '$lib/components/MemoryViewer.svelte';
	import GodotEngine from '$lib/components/GodotEngine.svelte';
	import FrequencySlider from '$lib/components/FrequencySlider.svelte';
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import { appState } from '$lib/AppState.svelte';

	// Svelte 5 runes (state + effects)
	let activeTab = $state('tab1'); // For mobile tabs
	let isRespawning = $state(false);
	let godotEngineComponent: GodotEngine;

	const TAB_KEY = 'retro.activeTab';
	let engine: any = $state(null);

	// Persist/restore active tab (mobile only)
	onMount(() => {
		try {
			const saved = localStorage.getItem(TAB_KEY);
			if (saved) activeTab = saved;
		} catch {}
	});

	// Handle engine ready callback
	function handleEngineReady(engineInstance: any) {
		engine = engineInstance;
	}

	async function handleRespawnShip() {
		if (isRespawning) return;

		try {
			isRespawning = true;
			await WebHelper.respawnShipWithCode(appState.code);
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
		const ids = ['tab1', 'tab2'];
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
</script>

<svelte:head>
	<script src="/SpessComputer.js"></script>
	<link id="-gd-engine-icon" rel="icon" type="image/png" href="SpessComputer.icon.png" />
	<link rel="apple-touch-icon" href="SpessComputer.apple-touch-icon.png" />
	<link rel="manifest" href="SpessComputer.manifest.json" />
</svelte:head>

<main class="flex flex-col lg:grid lg:grid-cols-[1fr_1fr] lg:grid-rows-[1fr_auto] gap-4 p-4 lg:h-[calc(100vh-2rem)]">
	<!-- VISUAL LINK: Top on mobile, top-left on desktop -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)] w-full order-first lg:row-span-1" style="height: 50vh; min-height: 300px;">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>VISUAL LINK</span>
		</div>
		<div
			class="bg-[#131318] shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_1px_rgba(255,184,107,0.08)]"
			style="height: calc(100% - 2.75rem);"
		>
			<GodotEngine bind:this={godotEngineComponent} onEngineReady={handleEngineReady} />
		</div>
		<!-- Corners -->
		{@render Corner('tl')}
		{@render Corner('tr')}
		{@render Corner('bl')}
		{@render Corner('br')}
	</section>

	<!-- CODE EDITOR: Desktop only, full right side -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)] hidden lg:block lg:row-span-2 lg:col-start-2">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>CODE EDITOR</span>
		</div>

		<!-- Code Editor Panel -->
		<div
			class="lg:h-[calc(100%-2.75rem)] bg-[#131318] p-2 sm:p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			<div class="flex h-full min-h-0 flex-col gap-3">
				<div class="flex-1 overflow-y-auto">
					<Asm6502Editor bind:value={appState.code} className="h-full" />
				</div>
				<button
					onclick={() => handleRespawnShip()}
					class="transform border border-[#ffb86b]/40 bg-[#0f0f12] px-3 sm:px-4 py-2 
					       text-xs sm:text-sm tracking-[0.15em] sm:tracking-[0.18em]
					       text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] transition hover:text-[#ffb86b]
					       hover:brightness-110 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50"
					disabled={isRespawning}
					type="button"
				>
					{isRespawning ? 'RESPAWNING...' : 'RESPAWN SHIP WITH CODE'}
				</button>
				{#if engine}
					<div class="mt-3">
						<FrequencySlider />
					</div>
				{/if}
			</div>
		</div>
		{@render Corner('tl')}
		{@render Corner('tr')}
		{@render Corner('bl')}
		{@render Corner('br')}
	</section>

	<!-- MEMORY VIEWER: Desktop only, bottom-left -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)] hidden lg:block lg:row-start-2 lg:col-start-1">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>MEMORY VIEWER</span>
		</div>

		<!-- Memory Viewer Panel -->
		<div
			class="lg:h-[calc(100%-2.75rem)] bg-[#131318] p-2 sm:p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			{#if engine}
				<div class="h-full flex flex-col">
					<div class="flex-1 overflow-y-auto">
						<MemoryViewer />
					</div>
				</div>
			{:else}
				<div class="h-full flex items-center justify-center text-[#ffb86b]/60 text-sm">
					<span>Engine not loaded</span>
				</div>
			{/if}
		</div>
		{@render Corner('tl')}
		{@render Corner('tr')}
		{@render Corner('bl')}
		{@render Corner('br')}
	</section>

	<!-- MOBILE TABBED INTERFACE: Mobile only -->
	<section class="relative bg-[#101014] shadow-[inset_0_0_0_2px_rgba(255,184,107,0.15)] lg:hidden order-last">
		<div
			class="flex items-center justify-between border-b border-[#ffb86b]/30 px-3 py-2 text-xs tracking-[0.2em]"
		>
			<span>CONTROL DECK</span>
		</div>

		<!-- Tabs -->
		<div
			class="flex gap-1 sm:gap-2 border-b border-[#ffb86b]/20 bg-[#0f0f12] px-2 sm:px-3 py-2"
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
			class="min-h-[80vh] bg-[#131318] p-2 sm:p-3 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.15),0_0_0_0_1px_rgba(255,184,107,0.08)]"
		>
			{#if activeTab === 'tab1'}
				<div
					id="tab-panel-1"
					role="tabpanel"
					aria-labelledby="tab1"
					aria-hidden="false"
					class="flex h-full min-h-0 flex-col gap-3"
					in:fade={{ duration: 150 }}
				>
					<div class="flex-1 min-h-[60vh] overflow-y-auto">
						<Asm6502Editor bind:value={appState.code} className="h-full" />
					</div>
					<button
						onclick={() => handleRespawnShip()}
						class="transform border border-[#ffb86b]/40 bg-[#0f0f12] px-3 sm:px-4 py-2 
						       text-xs sm:text-sm tracking-[0.15em] sm:tracking-[0.18em]
						       text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] transition hover:text-[#ffb86b]
						       hover:brightness-110 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50"
						disabled={isRespawning}
						type="button"
					>
						{isRespawning ? 'RESPAWNING...' : 'RESPAWN SHIP WITH CODE'}
					</button>
					{#if engine}
						<div class="mt-3">
							<FrequencySlider />
						</div>
					{/if}
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
						<div class="min-h-[60vh] flex-1 overflow-y-auto">
							<MemoryViewer />
						</div>
						<div class="mt-3">
							<FrequencySlider />
						</div>
					{:else}
						<div class="h-full flex items-center justify-center text-[#ffb86b]/60 text-sm">
							<span>Engine not loaded</span>
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
						<div class="min-h-[60vh] flex-1 overflow-y-auto" style="display: none;">
							<MemoryViewer />
						</div>
						<div class="mt-3" style="display: none;">
							<FrequencySlider />
						</div>
					{:else}
						<div class="h-full flex items-center justify-center text-[#ffb86b]/60 text-sm" style="display: none;">
							<span>Engine not loaded</span>
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
		class="transform border border-[#ffb86b]/40 bg-[#0f0f12] px-2 sm:px-3 py-1.5 sm:py-2 
		       text-xs sm:text-sm tracking-[0.15em] sm:tracking-[0.18em] flex-1 sm:flex-none
           text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] transition hover:brightness-110
           active:scale-[0.98] data-[active=true]:text-[#ffb86b] whitespace-nowrap"
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
