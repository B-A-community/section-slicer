# Нажимает «Копировать» в окне сессии, созданной clipboard.rb.
BACommunity::SectionSlicer::Session.current.dialog.execute_script(%q{document.getElementById('copy').click()})
puts 'copy clicked'
