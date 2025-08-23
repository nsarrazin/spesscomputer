<script lang="ts">
	import { onMount } from 'svelte';

	// Svelte 5 runes for state management
	let registers = $state<Record<'pc' | 'a' | 'x' | 'y' | 'p' | 'sp', number> | null>(null);
	let memoryPage = $state<ArrayBuffer | null>(null);
	let currentPage = $state(0);
	let followPC = $state(true);
	let pageInput = $state('0');
	let isLoading = $state(false);
	let updateInterval: ReturnType<typeof setInterval> | null = null;

	// Convert ArrayBuffer to Uint8Array for easier handling
	let memoryArray = $derived(memoryPage ? new Uint8Array(memoryPage) : null);

	// Calculate which page the PC is on
	let pcPage = $derived(registers ? Math.floor(registers.pc / 256) : 0);

	// Real-time update mechanism
	onMount(() => {
		function updateLoop() {
			updateData(); // your per-frame update
			requestAnimationFrame(updateLoop); // schedule next frame
		}

		requestAnimationFrame(updateLoop);
	});

	async function updateData() {
		if (isLoading) return; // Prevent overlapping requests

		try {
			isLoading = true;

			// Update registers
			const newRegisters = await WebHelper.getCurrentRegisters();
			registers = newRegisters;

			// Update current page if following PC
			if (followPC && registers) {
				const newPcPage = Math.floor(registers.pc / 256);
				if (newPcPage !== currentPage) {
					currentPage = newPcPage;
					pageInput = currentPage.toString();
				}
			}

			// Update memory page
			const newMemoryPage = followPC
				? await WebHelper.getPage(-1)
				: await WebHelper.getPage(currentPage);
			memoryPage = newMemoryPage;
		} catch (error) {
			console.warn('Failed to update memory viewer data:', error);
		} finally {
			isLoading = false;
		}
	}

	function goToPreviousPage() {
		if (currentPage > 0) {
			followPC = false;
			currentPage--;
			pageInput = currentPage.toString();
			updateData();
		}
	}

	function goToNextPage() {
		if (currentPage < 255) {
			followPC = false;
			currentPage++;
			pageInput = currentPage.toString();
			updateData();
		}
	}

	function goToPage() {
		const page = parseInt(pageInput);
		if (!isNaN(page) && page >= 0 && page <= 255) {
			followPC = false;
			currentPage = page;
			updateData();
		} else {
			// Reset input to current page if invalid
			pageInput = currentPage.toString();
		}
	}

	function toggleFollowPC() {
		followPC = !followPC;
		if (followPC && registers) {
			currentPage = Math.floor(registers.pc / 256);
			pageInput = currentPage.toString();
			updateData();
		}
	}

	function formatHex(value: number, digits: number = 2): string {
		return value.toString(16).toUpperCase().padStart(digits, '0');
	}

	function formatRegister(value: number): string {
		return '$' + formatHex(value, 2);
	}

	function formatAddress(address: number): string {
		return '$' + formatHex(address, 4);
	}

	// Check if an address is the current PC
	function isPCAddress(address: number): boolean {
		return registers !== null && registers.pc === address;
	}
</script>

<div class="flex h-full flex-col gap-3 font-mono text-sm max-w-2xl mx-auto">
	<!-- Registers Display -->
	<div class="flex flex-col gap-2">
		<div class="border-b border-[#ffb86b]/20 pb-1 text-xs tracking-[0.2em] text-[#ffb86b]/80">
			REGISTERS
		</div>
		{#if registers}
			<div class="grid grid-cols-3 gap-x-6 gap-y-2 text-xs">
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">PC:</span>
					<span class="text-[#ffb86b]">{formatAddress(registers.pc)}</span>
				</div>
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">A:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.a)}</span>
				</div>
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">X:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.x)}</span>
				</div>
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">Y:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.y)}</span>
				</div>
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">P:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.p)}</span>
				</div>
				<div class="inline-flex items-center gap-1">
					<span class="text-[#ffb86b]/60">SP:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.sp)}</span>
				</div>
			</div>
		{:else}
			<div class="text-xs text-[#ffb86b]/40">Loading registers...</div>
		{/if}
	</div>

	<!-- Page Navigation -->
	<div class="flex flex-col gap-2">
		<div class="border-b border-[#ffb86b]/20 pb-1 text-xs tracking-[0.2em] text-[#ffb86b]/80">
			MEMORY PAGE
		</div>
		<div class="flex items-center gap-2 text-xs">
			<button
				onclick={goToPreviousPage}
				disabled={currentPage === 0}
				class="border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[#ffb86b]/80
				       transition-colors hover:text-[#ffb86b] disabled:cursor-not-allowed
				       disabled:opacity-30"
			>
				←
			</button>

			<input
				type="text"
				bind:value={pageInput}
				onblur={goToPage}
				onkeydown={(e) => e.key === 'Enter' && goToPage()}
				class="w-12 border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-center
				       text-[#ffb86b] focus:border-[#ffb86b]/80 focus:outline-none"
				maxlength="3"
			/>

			<span class="text-[#ffb86b]/60">/255</span>

			<button
				onclick={goToNextPage}
				disabled={currentPage === 255}
				class="border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[#ffb86b]/80
				       transition-colors hover:text-[#ffb86b] disabled:cursor-not-allowed
				       disabled:opacity-30"
			>
				→
			</button>

			<button
				onclick={toggleFollowPC}
				class={`border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[#ffb86b]/80 transition-colors hover:text-[#ffb86b] ${followPC ? 'bg-[#ffb86b]/20' : ''}`}
			>
				Follow PC
			</button>
		</div>
	</div>

	<!-- Memory Grid -->
	<div class="min-h-0 flex-1">
		<div class="mb-2 border-b border-[#ffb86b]/20 pb-1 text-xs tracking-[0.2em] text-[#ffb86b]/80">
			MEMORY {formatHex(currentPage * 256, 4)} - {formatHex(currentPage * 256 + 255, 4)}
		</div>

		{#if memoryArray}
			<div class="h-full overflow-auto">
				<!-- Header with column numbers -->
				<div
					class="grid-cols-17 sticky top-0 mb-1 grid gap-1 bg-[#131318] text-xs text-[#ffb86b]/40"
				>
					<div class="text-right"></div>
					<!-- Empty cell for row headers, aligned right like row headers -->
					{#each Array(16) as _, i}
						<div class="text-center p-1">{formatHex(i, 1)}</div>
					{/each}
				</div>

				<!-- Memory rows -->
				{#each Array(16) as _, row}
					<div class="grid-cols-17 mb-1 grid gap-1 text-xs">
						<!-- Row header -->
						<div class="text-right text-[#ffb86b]/40 p-1">
							{formatHex(currentPage * 16 + row, 1)}0:
						</div>

						<!-- Memory cells -->
						{#each Array(16) as _, col}
							{@const address = currentPage * 256 + row * 16 + col}
							{@const byteIndex = row * 16 + col}
							{@const value = memoryArray[byteIndex] || 0}
							{@const isPC = isPCAddress(address)}

							<div
								class="p-1 text-center {isPC
									? 'bg-[#ffb86b]/30 font-bold text-[#000]'
									: 'text-[#ffb86b] hover:bg-[#ffb86b]/10'} 
								       cursor-default transition-none"
								title="Address: {formatAddress(address)}, Value: {value}"
							>
								{formatHex(value)}
							</div>
						{/each}
					</div>
				{/each}
			</div>
		{:else}
			<div class="flex h-32 items-center justify-center text-xs text-[#ffb86b]/40">
				Loading memory page...
			</div>
		{/if}
	</div>
</div>

<style>
	/* Custom grid for 16 columns + 1 header column */
	.grid-cols-17 {
		grid-template-columns: 3ch repeat(16, minmax(2ch, 1fr));
	}
</style>
