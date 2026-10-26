/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {
      colors: {
        // 校园低碳风主色：浅绿 + 米白
        mint: { 50: '#f0faf4', 100: '#dcf3e6', 200: '#b9e6cf', 300: '#8dd4b3', 400: '#5fb994', 500: '#3f9e7a', 600: '#2f8063', 700: '#286751' },
        cream: '#faf7f0',
      },
    },
  },
  plugins: [],
}
