/**
 * UniEvent — Main JS
 * Handles animations and utility functions
 */

document.addEventListener('DOMContentLoaded', () => {
    // Fade-in animation for event cards
    const cards = document.querySelectorAll('.event-card');
    const observer = new IntersectionObserver(
        (entries) => {
            entries.forEach((entry, i) => {
                if (entry.isIntersecting) {
                    entry.target.style.transitionDelay = `${i * 60}ms`;
                    entry.target.classList.add('visible');
                    observer.unobserve(entry.target);
                }
            });
        },
        { threshold: 0.1 }
    );
    cards.forEach((card) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(20px)';
        card.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
        observer.observe(card);
    });

    // Add visible class styles
    const style = document.createElement('style');
    style.textContent = `.event-card.visible { opacity: 1 !important; transform: translateY(0) !important; }`;
    document.head.appendChild(style);
});
