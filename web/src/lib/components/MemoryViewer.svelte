<script lang="ts">
	import { onMount } from 'svelte';

	// Svelte 5 runes for state management
	let registers = $state<Record<"pc" | "a" | "x" | "y" | "p" | "sp", number> | null>(null);
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
		// Initial load
		updateData();
		
		// Set up interval for regular updates (60 FPS but throttled to avoid lag)
		updateInterval = setInterval(updateData, 100); // 10 FPS for smooth updates without lag
		
		return () => {
			if (updateInterval) {
				clearInterval(updateInterval);
			}
		};
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

<div class="h-full flex flex-col gap-3 text-sm font-mono">
	<!-- Registers Display -->
	<div class="flex flex-col gap-2">
		<div class="text-xs tracking-[0.2em] text-[#ffb86b]/80 border-b border-[#ffb86b]/20 pb-1">
			REGISTERS
		</div>
		{#if registers}
			<div class="grid grid-cols-3 gap-2 text-xs">
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">PC:</span>
					<span class="text-[#ffb86b]">{formatAddress(registers.pc)}</span>
				</div>
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">A:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.a)}</span>
				</div>
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">X:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.x)}</span>
				</div>
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">Y:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.y)}</span>
				</div>
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">P:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.p)}</span>
				</div>
				<div class="flex justify-between">
					<span class="text-[#ffb86b]/60">SP:</span>
					<span class="text-[#ffb86b]">{formatRegister(registers.sp)}</span>
				</div>
			</div>
		{:else}
			<div class="text-[#ffb86b]/40 text-xs">Loading registers...</div>
		{/if}
	</div>

	<!-- Page Navigation -->
	<div class="flex flex-col gap-2">
		<div class="text-xs tracking-[0.2em] text-[#ffb86b]/80 border-b border-[#ffb86b]/20 pb-1">
			MEMORY PAGE
		</div>
		<div class="flex items-center gap-2 text-xs">
			<button
				onclick={goToPreviousPage}
				disabled={currentPage === 0}
				class="px-2 py-1 border border-[#ffb86b]/40 bg-[#0f0f12] text-[#ffb86b]/80 
				       hover:text-[#ffb86b] disabled:opacity-30 disabled:cursor-not-allowed
				       transition-colors"
			>
				←
			</button>
			
			<input
				type="text"
				bind:value={pageInput}
				onblur={goToPage}
				onkeydown={(e) => e.key === 'Enter' && goToPage()}
				class="w-12 px-2 py-1 bg-[#0f0f12] border border-[#ffb86b]/40 text-[#ffb86b] 
				       text-center focus:outline-none focus:border-[#ffb86b]/80"
				maxlength="3"
			/>
			
			<span class="text-[#ffb86b]/60">/255</span>
			
			<button
				onclick={goToNextPage}
				disabled={currentPage === 255}
				class="px-2 py-1 border border-[#ffb86b]/40 bg-[#0f0f12] text-[#ffb86b]/80 
				       hover:text-[#ffb86b] disabled:opacity-30 disabled:cursor-not-allowed
				       transition-colors"
			>
				→
			</button>
			
			<button
				onclick={toggleFollowPC}
				class={`px-2 py-1 border border-[#ffb86b]/40 bg-[#0f0f12] text-[#ffb86b]/80 hover:text-[#ffb86b] transition-colors ${followPC ? 'bg-[#ffb86b]/20' : ''}`}
			>
				Follow PC
			</button>
		</div>
	</div>

	<!-- Memory Grid -->
	<div class="flex-1 min-h-0">
		<div class="text-xs tracking-[0.2em] text-[#ffb86b]/80 border-b border-[#ffb86b]/20 pb-1 mb-2">
			MEMORY {formatHex(currentPage * 256, 4)} - {formatHex((currentPage * 256) + 255, 4)}
		</div>
		
		{#if memoryArray}
			<div class="h-full overflow-auto">
				<!-- Header with column numbers -->
				<div class="grid grid-cols-17 gap-1 text-xs text-[#ffb86b]/40 mb-1 sticky top-0 bg-[#131318]">
					<div></div> <!-- Empty cell for row headers -->
					{#each Array(16) as _, i}
						<div class="text-center">{formatHex(i, 1)}</div>
					{/each}
				</div>
				
				<!-- Memory rows -->
				{#each Array(16) as _, row}
					<div class="grid grid-cols-17 gap-1 text-xs mb-1">
						<!-- Row header -->
						<div class="text-[#ffb86b]/40 text-right">
							{formatHex(currentPage * 16 + row, 1)}0:
						</div>
						
						<!-- Memory cells -->
						{#each Array(16) as _, col}
							{@const address = currentPage * 256 + row * 16 + col}
							{@const byteIndex = row * 16 + col}
							{@const value = memoryArray[byteIndex] || 0}
							{@const isPC = isPCAddress(address)}
							
							<div
								class="text-center p-1 {isPC 
									? 'bg-[#ffb86b]/30 text-[#000] font-bold' 
									: 'text-[#ffb86b] hover:bg-[#ffb86b]/10'} 
								       transition-colors cursor-default"
								title="Address: {formatAddress(address)}, Value: {value}"
							>
								{formatHex(value)}
							</div>
						{/each}
					</div>
				{/each}
			</div>
		{:else}
			<div class="flex items-center justify-center h-32 text-[#ffb86b]/40 text-xs">
				Loading memory page...
			</div>
		{/if}
	</div>
</div>

<style>
	/* Custom grid for 16 columns + 1 header column */
	.grid-cols-17 {
		grid-template-columns: auto repeat(16, 1fr);
	}
</style>  