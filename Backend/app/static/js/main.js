// static/js/main.js
// =====================================================
// Mahrasoft Innovations — Script principal (module ES6)
// =====================================================

// Gestionnaire d'événements DOM ready
export const onReady = (fn) => {
    if (document.readyState !== 'loading') fn();
    else document.addEventListener('DOMContentLoaded', fn);
};

// Cache des éléments DOM
const dom = {
    spinner: document.getElementById('spinner'),
    navbar: document.querySelector('.navbar-modern'),
    backBtn: document.getElementById('backToTop')
};

// 1. Masquer le spinner
if (dom.spinner) dom.spinner.classList.add('hide');

// 2. Navbar effet scroll (avec throttle)
let ticking = false;
window.addEventListener('scroll', () => {
    if (!ticking) {
        requestAnimationFrame(() => {
            const scrolled = window.scrollY > 100;
            dom.navbar?.classList.toggle('scrolled', scrolled);
            dom.backBtn?.classList.toggle('d-none', !scrolled);
            ticking = false;
        });
        ticking = true;
    }
}, { passive: true });

// 3. Back to top
dom.backBtn?.addEventListener('click', (e) => {
    e.preventDefault();
    window.scrollTo({ top: 0, behavior: 'smooth' });
});

// 4. Dropdown au survol (desktop uniquement)
const initHoverDropdown = () => {
    if (window.innerWidth < 992) return;
    document.querySelectorAll('.navbar-modern .dropdown').forEach(dd => {
        // Nettoyage des anciens écouteurs
        if (dd._cleanup) dd._cleanup();

        const toggle = dd.querySelector('.dropdown-toggle');
        const menu = dd.querySelector('.dropdown-menu');
        if (!toggle || !menu) return;

        const show = () => {
            dd.classList.add('show');
            toggle.setAttribute('aria-expanded', 'true');
            menu.classList.add('show');
        };
        const hide = () => {
            dd.classList.remove('show');
            toggle.setAttribute('aria-expanded', 'false');
            menu.classList.remove('show');
        };

        dd.addEventListener('mouseenter', show);
        dd.addEventListener('mouseleave', hide);

        // Sauvegarde pour nettoyage
        dd._cleanup = () => {
            dd.removeEventListener('mouseenter', show);
            dd.removeEventListener('mouseleave', hide);
        };
    });
};

// 5. Gestion du redimensionnement (debounced)
let resizeTimer;
window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
        document.querySelectorAll('.navbar-modern .dropdown').forEach(dd => dd._cleanup?.());
        initHoverDropdown();
    }, 150);
}, { passive: true });

// 6. Fermeture du menu mobile après clic
onReady(() => {
    document.querySelectorAll('.navbar-nav .nav-link:not(.dropdown-toggle)').forEach(link => {
        link.addEventListener('click', () => {
            if (window.innerWidth < 992) {
                const nc = document.querySelector('.navbar-collapse');
                const bsCollapse = nc && bootstrap?.Collapse.getInstance(nc);
                if (bsCollapse) bsCollapse.hide();
            }
        });
    });
});

// 7. Initialisation conditionnelle d'AOS
onReady(() => {
    if (window.__mahrasoft?.useAOS) {
        import('https://unpkg.com/aos@2.3.1/dist/aos.js')
            .then(module => {
                module.default.init({
                    duration: 700,
                    easing: 'ease-in-out',
                    once: true,
                    offset: 60
                });
            })
            .catch(() => {}); // Silencieux en cas d'échec
    }
    initHoverDropdown();
});