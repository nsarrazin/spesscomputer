// This can be used to set page-specific meta data in the future
export const prerender = true;

// Default SEO configuration that can be overridden by individual pages
export const load = () => {
	return {
		meta: {
			title: 'SpessComputer - 6502 Assembly Space Computer Simulator',
			description: 'Program a retro 6502-based space computer to control spacecraft in this interactive programming simulator. Write assembly code, manage memory, and navigate through space.',
			url: '',
			image: '/SpessComputer-og.png',
			type: 'website'
		}
	};
};