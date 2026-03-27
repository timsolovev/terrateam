/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{html,js,svelte,ts}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        'sans': ['DejaVu Sans', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        'mono': ['JetBrains Mono', 'ui-monospace', 'monospace'],
      },
      colors: {
        'brand': {
          'primary': '#2563eb',
          'secondary': '#1a1a1a',
        }
      },
      backgroundColor: {
        'brand-primary': '#2563eb',
        'brand-secondary': '#1a1a1a',
      },
      textColor: {
        'brand-primary': '#2563eb',
        'brand-secondary': '#1a1a1a',
        'brand-tertiary': '#555555',
      },
      borderColor: {
        'brand-primary': '#2563eb',
        'brand-secondary': '#1a1a1a',
      },
    },
  },
  plugins: [],
}
