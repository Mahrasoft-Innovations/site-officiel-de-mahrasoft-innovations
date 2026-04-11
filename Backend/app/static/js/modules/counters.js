// static/js/modules/counters.js
// =====================================================
// Compteurs animés avec IntersectionObserver
// =====================================================

export function animateCounters() {
    const animate = (el) => {
        const raw = el.getAttribute('data-count');
        const suffix = el.getAttribute('data-suffix') || '+';
        const target = parseInt(raw, 10);
        const duration = 1800;
        const step = target / (duration / 16);
        let current = 0;

        const timer = setInterval(() => {
            current += step;
            if (current >= target) {
                el.textContent = target.toLocaleString() + suffix;
                clearInterval(timer);
            } else {
                el.textContent = Math.floor(current).toLocaleString() + suffix;
            }
        }, 16);
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                animate(entry.target);
                observer.unobserve(entry.target);
            }
        });
    }, { threshold: 0.3 });

    document.querySelectorAll('[data-count]').forEach(el => observer.observe(el));
}